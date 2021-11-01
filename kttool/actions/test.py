from collections import namedtuple
import os
from pathlib import Path
from typing import List, Tuple
from kttool.base import Action
import json, subprocess, shlex
from kttool.logger import color_cyan, color_green, color_red, log, log_cyan
import re, time, psutil
from kttool.utils import  make_list_equal, register_subprocess


def compare_entity( lhs: str,  rhs: str) -> Tuple[bool, str]:
    if lhs == rhs:
        return True, f'{lhs} '
    return False, f'{color_red(lhs)}{color_green(rhs)} '


Sample = namedtuple('Sample', 
    ['index', 'input_file', 'output_file']
)

class Test(Action):
    REQUIRED_CONFIG = True

    def _compare_samples(self, samples: List[Sample]) -> None:
        rusage_denom = 1 << 20
        actual = []
        expected = []
        diff = []

        for sample in samples:
            is_ac = True
            actual.clear()
            expected.clear()
            diff.clear()
            try:
                with open(sample.output_file, 'r') as f:
                    expected = [l.strip(" \n") for l in f.readlines()]
                with open(sample.input_file, 'rb') as f:    
                    raw_input = f.read()
                # log_cyan(f'running {self.script}')
                p = subprocess.Popen([self.script, '-'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, shell=False, 
                    preexec_fn=os.setsid)
                register_subprocess(p)
                proc = psutil.Process(p.pid)
                mem_used = proc.memory_info().rss / rusage_denom
                start_time = time.perf_counter()
                raw_output = p.communicate(raw_input)[0].decode()
                p.wait()
                taken = time.perf_counter()  - start_time
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
                        is_good, now_diff = compare_entity(rhs,lhs)
                        is_ac &= is_good
                        current_diff += now_diff

                    diff.append(current_diff)
                if is_ac:
                    log(color_green(f'Test Case #{sample.index}: {"Accepted".ljust(13, " ")} ... {taken:.3f} s   {mem_used:.2f} M'))
                else:
                    log(color_red(f'Test Case #{sample.index}: {"Wrong Answer".ljust(13, " ")} ... {taken:.3f} s   {mem_used:.2f} M'))
                    log(color_cyan('--- Input ---'))
                    log(raw_input.decode())
                    log(color_cyan('--- Diff ---'))
                    for i in range(len(diff)):
                        log(diff[i])

            except Exception as e:
                log(color_red(f'Test case #{sample.index}: Runtime Error {e}'))

    
    def _gather_samples(self) -> List[Sample]:
        input_files = [x for x in self.cwd.iterdir() if x.is_file() and x.stem.startswith('in')]
        output_files = [x for x in self.cwd.iterdir() if x.is_file() and x.stem.startswith('ans')]
        usable_samples: List[Sample] = []


        pattern = re.compile(r"\d+")
        for input_file in input_files:
            idx = int(pattern.search(str(input_file)).group(0))
            for output_file in output_files:
                if idx == int(pattern.search(str(output_file)).group(0)):
                    usable_samples.append(Sample(
                        index=idx, 
                        input_file=input_file, 
                        output_file=output_file)
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
        self.detect_file_name()

        # Get sample files that match the condition
        usable_samples = self._gather_samples()
        # run test
        log(f'Problem ID : {color_cyan(self.get_problem_id())}')
        log(f'Lanuage    : {self.lang}')
        if self.pre_script:
            log_cyan(f'running {self.pre_script}')
            subprocess.check_call(shlex.split(self.pre_script))

        self._compare_samples(usable_samples)
        
        if self.post_script:
            log_cyan(f'running {self.post_script}')
            subprocess.check_call(shlex.split(self.post_script))