import re
from typing import Any
from bs4 import BeautifulSoup
from bs4.element import ResultSet
from kttool.base import Action
from reprint import output
import time
from kttool.logger import color_cyan, color_green, color_red, log_green, log_red
import emoji, requests


AC_ICON = ':heavy_check_mark:'
RJ_ICON = ':heavy_multiplication_x:'
SK_ICON = ':white_medium_square:'


class Submit(Action):
    '''Handle kt submit action to push the file to kattis website'''

    REQUIRED_CONFIG = True

    submission_id: str

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.submission_id = ''


    def is_finished(self, output_lines: output, result: ResultSet, status: str,  run_time: str) -> bool: 
        """ Judge whether the result and status obtained from kattis submission
        page has indicated whether the solution judgement has been done

        Parameters
        ----------
        output_lines : output
            console object to print multiple lines inline
        result : ResultSet[Any]
            List of object corresponding to the HTML component of test case on kattis submission
        status : str
            Status obtained from kattis submission page
        run_time : str
            Time taken obtained from kattis submissione page

        Returns
        -------
        bool
            Whether if the task has been finished marking from kattis
        """

        tot_res = len(result)
        ac_ct = 0
        is_ac = True
        rejected = False
        finished = False
        _status = status

        for res in result:
            _class = res.get('class', None)
            if _class:
                if _class[0] == 'accepted':
                    ac_ct += 1
                else: # rejected
                    rejected = True
                    is_ac = False
                    break
        res = [AC_ICON] * ac_ct

        if rejected:
            res.append(RJ_ICON)
        while len(res) < tot_res:
            res.append(SK_ICON)

        if rejected:
            finished = True
        else:
            finished = ac_ct == tot_res

        if status == 'Compiling':
            finished = False
        elif status == 'Compile Error':
            _status = color_red(status)
        elif not finished:
            _status = color_cyan(status)
        else:
            if status in {'Running', 'New'}: # status text not updated, lets try again
                finished = False
            elif is_ac:
                _status = color_green(status)
            else:
                _status = color_red(status)

        output_lines['current time      '] = f"{time.strftime('%02l:%M%p %Z on %b %d, %Y')}"
        output_lines['language          '] = f'{self.lang}' 
        output_lines['problem id        '] = self.get_problem_id()
        output_lines['running time      '] = f'{run_time}' 
        output_lines['submission id     '] = self.submission_id
        output_lines['submission result '] = f'{_status}'
        output_lines['test cases        '] = f"{emoji.emojize(' '.join(res))}"
        return finished
        


    def _render_result(self,  submission_url_ret: str) -> None:
        """ Continuously polling for result from `submission_url_ret`

        Parameters
        ----------
        submission_url_ret : str
            url for the submission to be checked
        """

        time_out = 60
        cur_time = 0
        done  = False
        sleep_time = 0.4

        with output(output_type='dict') as output_lines:
            while cur_time < time_out and not done:
                try:
                    self.login()
                    page = self.request_get(submission_url_ret)
                    soup = BeautifulSoup(page.content, 'html.parser')
                    submission_data = soup.find('div', class_='testcases')
                    if submission_data is not None:
                        submission_ret = submission_data.find_all('span')
                        status_ret = soup.find('td', class_='status middle').find('span').text
                        runtime_ret = soup.find('td', class_='runtime middle').text
                        done = self.is_finished(output_lines, submission_ret, status_ret, runtime_ret)
                except Exception as e:
                    log_red(f'Internal error: {e!r}')

                time.sleep(sleep_time)
                cur_time += sleep_time

            

    def _act(self) -> None:
        '''Submit the code file for kattis judge'''
        problem_id = self.get_problem_id()
        self.detect_file_name()
        data = {'submit': 'true',
            'submit_ctr': 2,
            'language': self.lang,
            'mainclass': '',
            'problem': problem_id,
            'tag': '',
            'script': 'true'}
        files = []
        with open(self.file_name) as sub_file:
            files.append(('sub_file[]',
                              (self.file_name.name,
                               sub_file.read(),
                               'application/octet-stream')))
        submit_url = self.get_url('submissionurl', 'submit')
        self.login()
        ret = self.request_post(submit_url, data=data, files=files)
        if ret.status_code != 200:
            if ret.status_code == 403:
                err = 'Access denied (403)'
            elif ret.status_code == 404:
                err = 'Incorrect submit URL (404)'
            else:
                err = f'Status code: {ret.status_code}'
            raise RuntimeError(f'Submission failed: {err}')
        submissions_url  = self.get_url('submissionsurl', 'submissions')
        submit_response = ret.content.decode('utf-8').replace('<br />', '\n')
        self.submission_id = re.search(r'Submission ID: (\d+)', submit_response).group(1)
        log_green('Submission successful')
        submission_url_ret  = f'{submissions_url}/{self.submission_id}' 
        self._render_result(submission_url_ret)