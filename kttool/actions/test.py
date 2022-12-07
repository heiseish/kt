import json
import os
import re
import shlex
import subprocess
import tempfile
import time
from collections import namedtuple
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple

import psutil

from ..base import Action
from ..logger import (
    color_cyan, color_green, color_red, log, log_cyan, log_green, log_red,
    strike_through
)
from ..utils import (launch_subprocess, make_list_equal)

__all__ = ['Test']

AC = "Accepted".ljust(13, " ")
WA = "Wrong Answer".ljust(13, " ")


@dataclass
class Sample:
    index: int
    input_file: Path
    output_file: Path


class Test(Action):
    """Handle test command, run the code with local input and test against local output
    """
    REQUIRED_CONFIG = True

    def _compare_samples(self, samples: List[Sample]) -> None:
        rusage_denom = 1 << 20

        for sample in samples:
            is_ac = True
            actual = []
            expected = []
            diff = []
            try:
                with open(sample.output_file, 'r') as f:
                    expected = [l.strip(" \n") for l in f.readlines()]
                with open(sample.input_file, 'rb') as f:
                    raw_input_fixture = f.read()
                p = launch_subprocess(
                    shlex.split(f'{self.script} -'),
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    shell=False,
                    preexec_fn=os.setsid
                )
                proc = psutil.Process(p.pid)
                mem_used = proc.memory_info().rss / rusage_denom
                start_time = time.perf_counter()
                raw_output = p.communicate(raw_input_fixture)[0].decode()
                p.wait()
                taken = time.perf_counter() - start_time
                actual = [z.strip(" \n") for z in raw_output.split('\n')]
                make_list_equal(actual, expected)

                for i in range(len(expected)):
                    ''' 
                    Compare the values line by line
                    For each line, compare the values from left to right. 
                    '''
                    ith_line_exp = [z for z in expected[i].split(' ')]
                    ith_line_actual = [z for z in actual[i].split(' ')]

                    make_list_equal(ith_line_exp, ith_line_actual)
                    current_diff = ''
                    for j in range(len(ith_line_exp)):
                        lhs = ith_line_exp[j]
                        rhs = ith_line_actual[j]
                        is_good, now_diff = self._compare_entity(rhs, lhs)
                        is_ac &= is_good
                        current_diff += now_diff

                    diff.append(current_diff)

                if is_ac:
                    log_green(
                        f'Test Case #{sample.index}: {AC} ... {taken:.3f} s   {mem_used:.2f} M'
                    )
                else:
                    log_red(
                        f'Test Case #{sample.index}: {WA} ... {taken:.3f} s   {mem_used:.2f} M'
                    )
                    log_cyan('--- Input ---')
                    log(raw_input_fixture.decode())
                    log_cyan('--- Diff ---')
                    for i in range(len(diff)):
                        log(diff[i])

            except subprocess.CalledProcessError as e:
                log_red(f'Test case #{sample.index}: Runtime Error {e!r}')
            except Exception as e:
                self._record_unexpected_exception(sample, e)

    @staticmethod
    def _record_unexpected_exception(sample: Sample, ex: Exception) -> None:
        import traceback
        p = Path(tempfile.gettempdir())
        p.mkdir(parents=True, exist_ok=True)
        tmp_file = p / 'kt_test.log'
        with open(tmp_file, 'w+') as f:
            f.write(traceback.format_exc())
        log_red(
            f'Test case #{sample.index}: Internal Error {ex!r}. More info at {tmp_file}'
        )

    def _gather_samples(self) -> List[Sample]:
        input_files = [
            x for x in self.cwd.iterdir()
            if x.is_file() and x.stem.startswith('in')
        ]
        output_files = [
            x for x in self.cwd.iterdir()
            if x.is_file() and x.stem.startswith('ans')
        ]
        usable_samples: List[Sample] = []

        in_pattern = re.compile("in(\d+).txt")
        ans_pattern = re.compile("ans(\d+).txt")
        for input_file in input_files:
            idx = int(in_pattern.search(input_file.name).group(1))
            for output_file in output_files:
                if idx == int(ans_pattern.search(output_file.name).group(1)):
                    usable_samples.append(
                        Sample(
                            index=idx,
                            input_file=Path(input_file).absolute(),
                            output_file=Path(output_file).absolute()
                        )
                    )
                    break
        # run test from ascending number of file index
        return sorted(usable_samples, key=lambda x: x.index)

    def _act(self) -> None:
        """ Run the executable file against sample input and output files present in the folder
        The sample files will only be recognized if the conditions hold:
        - Naming style should be in{idx}.txt and ans{txt}.txt
        - for in{idx}.txt, there must exist a ans{idx}.txt with the same `idx`
        """
        if not self._detect_code_files():
            return

        # Get sample files that match the condition
        usable_samples = self._gather_samples()
        # run test
        log(f'Problem ID : {color_cyan(self._get_problem_id())}')
        log(f'Lanuage    : {self.lang}')
        if self.pre_script:
            log_cyan(f'running {self.pre_script}')
            subprocess.check_call(shlex.split(self.pre_script))

        self._compare_samples(usable_samples)

        if self.post_script:
            log_cyan(f'running {self.post_script}')
            subprocess.check_call(shlex.split(self.post_script))

    @staticmethod
    def _compare_entity(lhs: str, rhs: str) -> Tuple[bool, str]:
        if lhs == rhs:
            return True, f'{lhs} '
        return False, f'{color_red(strike_through(lhs))}{color_green(rhs)} '