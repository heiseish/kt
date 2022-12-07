import json
import shutil
from collections import namedtuple
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

import bs4
import requests
from bs4 import BeautifulSoup

from ..base import Action, require_login
from ..logger import log, log_green, log_red
from ..utils import HEADERS, MAP_TEMPLATE_TO_PLANG

__all__ = ['Gen']


@dataclass(frozen=True)
class _SampleData:
    problem_id: str
    is_input: bool
    sample_id: str
    data: str


class Gen(Action):
    ''' Handle `gen` command for kt_tool '''
    REQUIRED_CONFIG = True

    problem_id: str
    __slots__ = 'problem_id'

    def __init__(self, problem_id: str, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.problem_id = self._parse_problem_id(problem_id)

    @staticmethod
    def _write_sample(sample_data: _SampleData, root_path: Path) -> None:
        """ Write input/output sample to file. This is used for multiprocess pool to generate input/output files
        Parameters
        ----------
        sample_data : SampleData
            a tuple representing index, string data, problem id and a boolean declaring whether current
        file is input (False if the file is output)
        """
        file_name_prefix = 'in' if sample_data.is_input else 'ans'
        file_name = root_path / f'{sample_data.problem_id}/{file_name_prefix}{sample_data.sample_id}.txt'

        with open(file_name, 'w+') as f:
            f.write(sample_data.data)

    @staticmethod
    def _parse_problem_id(raw_input: str) -> Optional[str]:
        def _is_url(s: str) -> bool:
            return 'open.kattis.com' in s

        def _parse_problem_id_from_url(url_like: str) -> Optional[str]:
            parts = url_like.split('/')
            if len(parts) == 0:
                return None
            return parts[-1]

        return raw_input if not _is_url(
            raw_input
        ) else _parse_problem_id_from_url(raw_input)

    def _parse_sample_data(self, data: bs4.ResultSet) -> List[_SampleData]:
        sample_data = []
        for i in range(len(data)):
            if i & 1:
                sample_data.append(
                    _SampleData(
                        sample_id=i // 2 + 1,
                        data=data[i].text,
                        problem_id=self.problem_id,
                        is_input=False
                    )
                )
            else:
                sample_data.append(
                    _SampleData(
                        sample_id=i // 2 + 1,
                        data=data[i].text,
                        problem_id=self.problem_id,
                        is_input=True
                    )
                )
        return sample_data

    @require_login
    def _generate_samples(self) -> None:
        """ Generate sample input file for `self.problem_id`
        The basic flow is to scrape the problem task page and retrieve the relevent fields
        Generate the sample files to problem id folder
        For example, if the problem id is distinctivecharacter, `kt gen` will
        - Generate a folder called distinctivecharacter
        - Get sample intput, output from problem task page and generate to distinctivecharacter/, in this
        example there will be 4 files generated
        + distinctivecharacter/in1.txt
        + distinctivecharacter/ans1.txt
        + distinctivecharacter/in2.txt
        + distinctivecharacter/ans2.txt
        - Generate a template file (distinctivecharacter.cpp) if a template file is provided in the .ktconfig file
        """
        url = self.get_problem_url()
        page = requests.get(url, cookies=self.cookies, headers=HEADERS)
        soup = BeautifulSoup(page.content, 'html.parser')
        data = soup.find_all('pre')
        sample_data = self._parse_sample_data(data)

        assert len(data) % 2 == 0, 'Internal error: Number of sample input '\
            ' is not equal to number of sample output'

        for sample in sample_data:
            self._write_sample(sample, self.cwd)

        log_green(
            f'Generate {len(sample_data) // 2} sample(s) to {self.problem_id}'
        )

    def _get_problem_id(self) -> str:
        return self.problem_id

    def _generate_template_file(self):
        """_summary_
        """
        template_file = {}
        if not self.kt_config.is_file():
            log_red(
                '.ktconfig file has not been set up so no template was generated. '
                'Please use `kt config` to set up a template file'
            )
            return

        template_file = self.load_kt_config()

        for k, template in template_file.items():
            if template.get('default', None):
                template_file_location = template.get('path')
                if not template_file_location or not Path(
                    template_file_location
                ).is_file():
                    continue
                target_location = self.cwd / f'{self.problem_id}/{self.problem_id}.{MAP_TEMPLATE_TO_PLANG[k].extension}'
                target_location.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(template_file_location, target_location)
                log_green('Template file has been generated')
                return
        log_red(f'No default template detected in {self.kt_config}')

    def _act(self) -> None:
        if self.problem_id is None:
            log_red(f'Unable to parse problem id')
            return

        log(f'Problem is {self.problem_id}')
        problem_dir = self.cwd / self.problem_id
        problem_dir.mkdir(parents=True, exist_ok=True)
        self._generate_samples()
        self._generate_template_file()
