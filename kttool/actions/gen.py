from pathlib import Path
from kttool.base import Action
import requests
from bs4 import BeautifulSoup
from dataclasses import dataclass
from concurrent.futures import ProcessPoolExecutor
import json
from kttool.logger import log, log_green, log_red
import shutil
from collections import namedtuple

from kttool.utils import HEADERS, MAP_TEMPLATE_TO_PLANG



@dataclass
class SampleData:
    problem_id: str = ''
    is_in: bool = True
    sample_id: str = ''
    data: str = ''



def write_samples(sample_data: SampleData) -> None:
    """ Write input/output sample to file. This is used for multiprocess pool to generate input/output files
    Parameters
    ----------
    sample_data : SampleData
        a tuple representing index, string data, problem id and a boolean declaring whether current
    file is input (False if the file is output)
    """
    file_name_prefix = 'in' if sample_data.is_in else 'ans'
    file_name = f'{sample_data.problem_id}/{file_name_prefix}{sample_data.sample_id}.txt'

    with open(file_name, 'w+') as f:
        f.write(sample_data.data)

class Gen(Action):
    REQUIRED_CONFIG = True

    ''' Handle `gen` command for kt_tool '''
    problem_id: str

    __slots__ = 'problem_id'

        
    ''' Handle `gen` command for kt_tool '''
    def __init__(self, problem_id: str, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.problem_id = problem_id
    
    def _gen_samples(self) -> None:
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
        template_file = {}
        sample_data = []
        i = 0

        self.login()
        url = self.get_problem_url()
        page = requests.get(url, cookies=self.cookies, headers=HEADERS)
        soup = BeautifulSoup(page.content, 'html.parser')
        data = soup.find_all('pre')

        for i in range(len(data)):
            if i & 1:
                sample_data.append(SampleData(sample_id=i // 2 + 1, data=data[i].text, problem_id=self.problem_id, is_in=False))
            else:
                sample_data.append(SampleData(sample_id=i // 2 + 1, data=data[i].text, problem_id=self.problem_id, is_in=True))

        assert len(data) % 2 == 0, 'Internal error: Number of sample input '\
            ' is not equal to number of sample output'

        with ProcessPoolExecutor(max_workers=4) as executor:
            executor.map(write_samples, sample_data)

        log_green(f'Generate {len(sample_data) // 2} sample(s) to {self.problem_id}')
        if not self.kt_config.is_file():
            log_red('.ktconfig file has not been set up so no template was generated. '
            'Please use `kt config` to set up a template file')
            return

        

        template_file = self.load_kt_config()

        for k, template in template_file.items():
            if template.get('default', False):
                shutil.copyfile(template.get('path'), f'{self.problem_id}/{self.problem_id}.{MAP_TEMPLATE_TO_PLANG[k].extension}')
                log_green('Template file has been generated')
                return
        log_red(f'No default template detected in {self.kt_config}')

    def get_problem_id(self) -> str:
        return self.problem_id

    def _act(self) -> None:
        log(f'Problem is {self.problem_id}')
        problem_dir = self.cwd / self.problem_id
        problem_dir.mkdir(parents=True, exist_ok=True)
        self._gen_samples()