from __future__ import annotations
import re
import time
from dataclasses import dataclass
from typing import Optional
from typing_extensions import final
import emoji
import requests
from bs4 import BeautifulSoup
from bs4.element import ResultSet
from reprint import output
from ..base import Action, require_login
from ..logger import color_cyan, color_green, color_red, log_cyan, log_green

__all__ = ['Submit']

AC_ICON = ':heavy_check_mark:'
RJ_ICON = ':heavy_multiplication_x:'
SK_ICON = ':white_medium_square:'


@dataclass
class SubmissionResult:
    submission_id: str
    submission_url: str


@dataclass
class SubmissionParseResult:
    test_cases: ResultSet
    overall_status: str
    run_time: str


@dataclass
class SubmissionVerdict:
    verdict: str
    num_test_cases: int
    ac_test_cases: int
    is_done: bool
    run_time: str
    is_rejected: bool


@final
class Submit(Action):
    """Usage: kt submit

    Submit the current code in the directionary (assumed to be generated using kttool) to the host and check for result. 
    If multiple suitables runable code files are detected, the user can specify which one to submit
    """
    REQUIRED_CONFIG = True

    _PENDING_STATE = {
        'Compiling', 'Running', 'New', 'Waiting for compile', 'Waiting for run'
    }
    _REJECTED_STATE = {
        'Compile Error', 'Wrong Answer', 'Time Limit Exceeded', 'Judge Error',
        'Memory Limit Exceeded', 'Output Limit Exceeded', 'Illegal Function',
        'Run-Time Error'
    }
    _ACCEPTED_STATE = {'Accepted'}

    @staticmethod
    def _parse_verdict(
        parsed_result: SubmissionParseResult
    ) -> SubmissionVerdict | None:
        if parsed_result.test_cases is None:
            return None
        num_test_cases = len(parsed_result.test_cases)
        ac_ct = 0
        finished = False
        status = parsed_result.overall_status
        rejected = False

        for res in parsed_result.test_cases:
            _class = res.get('class', None)
            if not _class:
                continue
            if 'is-accepted' in _class:
                ac_ct += 1
            elif 'is-empty' in _class:
                continue
            else:  # rejected
                rejected = True
                break

        if status in Submit._REJECTED_STATE:
            _status = color_red(status)
            finished = True
        elif status in Submit._ACCEPTED_STATE:
            _status = color_green(status)
            finished = True
        else:
            _status = color_cyan(status)

        return SubmissionVerdict(
            verdict=_status,
            num_test_cases=num_test_cases,
            ac_test_cases=ac_ct,
            is_done=finished,
            run_time=parsed_result.run_time,
            is_rejected=rejected
        )

    def _is_finished(
        self, output_lines: output.SignalDict,
        submission_result: SubmissionResult,
        parsed_result: Optional[SubmissionParseResult]
    ) -> bool:
        """ Judge whether the result and status obtained from kattis submission
        page has indicated whether the solution judgement has been done

        Parameters
        ----------
        output_lines : output
            console object to print multiple lines inline
        result : SubmissionParseResult
            Parsed result objects

        Returns
        -------
        bool
            Whether if the task has been finished marking from kattis
        """
        if parsed_result is None:
            return False

        verdict: None | SubmissionVerdict = self._parse_verdict(parsed_result)
        if verdict is None:
            return False
        res = [AC_ICON] * verdict.ac_test_cases
        if verdict.is_rejected:
            res.append(RJ_ICON)
        while len(res) < verdict.num_test_cases:
            res.append(SK_ICON)

        display_output = {
            'current time': time.strftime('%02l:%M%p %Z on %b %d, %Y'),
            'language': self.lang,
            'problem id': self._get_problem_id(),
            'running time': parsed_result.run_time,
            'submission id': submission_result.submission_id,
            'submission result': verdict.verdict,
            'test cases': emoji.emojize(' '.join(res), use_aliases=True)
        }
        for k, v in display_output.items():
            output_lines[k.ljust(20)] = str(v)

        return verdict.is_done

    @require_login
    def _query_submission_id_url(
        self, submission_result: SubmissionResult
    ) -> BeautifulSoup:
        page = self._request_get(submission_result.submission_url)
        soup = BeautifulSoup(page.content, 'html.parser')
        return soup

    def _parse_results_from_soup(
        self, soup: BeautifulSoup
    ) -> Optional[SubmissionParseResult]:

        try:
            submission_data = soup.find(
                'div', class_='status testcase testcase-row'
            )
            status_ret = soup.find(
                'div', class_='status'
            ).next_element.next_element

            runtime_ret = status_ret.next_element
            return SubmissionParseResult(
                submission_data, status_ret.text, runtime_ret.text
            )
        except:
            ...

    def _render_result(self, submission_result: SubmissionResult) -> None:
        """ Continuously polling for result from `submission_url_ret`

        Parameters
        ----------
        submission_url_ret : str
            url for the submission to be checked
        """
        time_out = 60
        cur_time = 0
        done = False
        sleep_time = 0.4

        with output(output_type='dict') as output_lines:
            while cur_time < time_out:
                try:
                    soup: BeautifulSoup = self._query_submission_id_url(
                        submission_result
                    )
                    result = self._parse_results_from_soup(soup)
                    done = self._is_finished(
                        output_lines, submission_result, result
                    )
                    if done:
                        break
                except Exception as ex:
                    log_cyan(f'Waitinng for result...')

                time.sleep(sleep_time)
                cur_time += sleep_time

    @require_login
    def _submit_code_file(self) -> Optional[SubmissionResult]:
        problem_id = self._get_problem_id()
        if not self._detect_code_files():
            return None
        data = {
            'submit': 'true',
            'submit_ctr': 2,
            'language': self.lang,
            'mainclass': '',
            'problem': problem_id,
            'tag': '',
            'script': 'true'
        }
        files = []
        with open(self.file_name) as sub_file:
            files.append(
                (
                    'sub_file[]', (
                        self.file_name.name, sub_file.read(),
                        'application/octet-stream'
                    )
                )
            )
        submit_url = self.get_url('submissionurl', 'submit')
        ret = self._request_post(submit_url, data=data, files=files)
        self._check_status_code(ret)
        submissions_base_url = self.get_url('submissionsurl', 'submissions')
        submit_response = ret.content.decode('utf-8').replace('<br />', '\n')
        submission_id = re.search(r'Submission ID: (\d+)',
                                  submit_response).group(1)
        return SubmissionResult(
            submission_id, f'{submissions_base_url}/{submission_id}'
        )

    def _check_status_code(self, ret: requests.Response):
        if ret.status_code != 200:
            if ret.status_code == 403:
                err = 'Access denied (403)'
            elif ret.status_code == 404:
                err = 'Incorrect submit URL (404)'
            else:
                err = f'Status code: {ret.status_code}'
            raise RuntimeError(f'Submission failed: {err}')

    def _act(self) -> None:
        '''Submit the code file for kattis judge'''
        submission_result: SubmissionResult = self._submit_code_file()
        if submission_result is None:
            return
        log_green(
            f'Submission successful -- id {submission_result.submission_id}'
        )
        self._render_result(submission_result)
