#cython: language_level=3, c_str_type=unicode, c_str_encoding=utf8
import sys
from typing import List, Tuple
from libcpp.string cimport string
from libcpp.vector cimport vector
from libcpp cimport bool as bool_t
from cython.view cimport array as cvarray
import requests
import os
import re
import time
from bs4 import BeautifulSoup
import multiprocessing
import concurrent.futures
if sys.version_info[0] >= 3:
    import configparser
else:
    import ConfigParser as configparser
from html.parser import HTMLParser
import emoji

__all__ = [
    'arg_parse',
    'color_red'
]

_HEADERS = {'User-Agent': 'kt'}

BLACK, RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN, WHITE = range(90, 98)
BOLD_SEQ = '\033[1m'
RESET_SEQ = '\033[0m'
COLOR_SEQ = '\033[6;{}m'


cdef str _color_cyan(str text):
    return f'{COLOR_SEQ.format(CYAN)}{text}{RESET_SEQ}'

cdef str _color_green(str text):
    return f'{COLOR_SEQ.format(GREEN)}{text}{RESET_SEQ}'
    
cdef str _color_red(str text):
    return f'{COLOR_SEQ.format(RED)}{text}{RESET_SEQ}'

cdef class ConfigError(Exception):
    pass

cdef class Action(object):
    cdef str config_path
    cdef str host_name 
    cdef str submit_url
    cdef str submissions_url
    cdef object cfg
    cdef object cookies

    def __cinit__(self):
        self.config_path = os.path.join(os.getenv('HOME'), '.kattisrc')

    cdef str get_url(self, str option, str default):
        cdef str kattis_host
        if self.cfg.has_option('kattis', option):
            return self.cfg.get('kattis', option)
        else:
            kattis_host = self.cfg.get('kattis', 'hostname')
            return f'https://{kattis_host}/{default}'


    cdef read_config_from_file(self):
        self.cfg = configparser.ConfigParser()
        if not os.path.exists(self.config_path):
            raise RuntimeError(f'No valid config file at {self.config_path}')
        self.cfg.read(self.config_path)
        username = self.cfg.get('user', 'username')
        password = token = None
        try:
            password = self.cfg.get('user', 'password')
        except configparser.NoOptionError:
            pass
        try:
            token = self.cfg.get('user', 'token')
        except configparser.NoOptionError:
            pass
        if password is None and token is None:
            raise ConfigError('''\
        Your .kattisrc file appears corrupted. It must provide a token (or a
        KATTIS password).
        Please download a new .kattisrc file''')


    cdef login(self):
        username = self.cfg.get('user', 'username')
        password = token = None
        try:
            password = self.cfg.get('user', 'password')
        except configparser.NoOptionError:
            pass
        try:
            token = self.cfg.get('user', 'token')
        except configparser.NoOptionError:
            pass
        cdef str login_url = self.get_url('loginurl', 'login')
        login_args = {'user': username, 'script': 'true'}
        if password:
            login_args['password'] = password
        if token:
            login_args['token'] = token
        login_reply = requests.post(login_url, data=login_args, headers=_HEADERS)
        cdef str err
        if not login_reply.status_code == 200:
            if login_reply.status_code == 403:
                err = 'Incorrect username or password/token (403)'
            elif login_reply.status_code == 404:
                err = 'Incorrect login URL (404)'
            else:
                err = f'Status code: {login_reply.status_code}'
            raise RuntimeError(f'Login failed. {err}')
        self.cookies = login_reply.cookies
        # print(_color_green('Login successfully'))



    cdef _act(self):
        raise NotImplementedError

    def act(self):
        self.read_config_from_file()
        self._act()


cdef cwrite_samples(sample_data: Tuple[int, str, str, bool]):
    cdef str file_name_prefix = 'in' if sample_data[3] else 'ans'
    cdef str file_name = f'{sample_data[2]}/{file_name_prefix}{sample_data[0]}.txt'
    with open(file_name, 'w') as f:
        f.write(sample_data[1])

def write_samples(sample_data: Tuple[int, str, str, bool]):
    cwrite_samples(sample_data)

cdef class Gen(Action):
    cdef str _problem_id
    cdef str _url 

    def __cinit__(self, str problem_id, str domain = 'open'):
        self._problem_id = problem_id
        self._url = f'https://{domain}.kattis.com/problems/{self._problem_id}'

    cdef _gen_samples(self):
        self.login()
        page = requests.get(self._url, cookies=self.cookies, headers=_HEADERS)
        soup = BeautifulSoup(page.content, 'html.parser')
        data = soup.find_all('pre')

        sample_data: List[Tuple[int, str, str, bool]] = []
        for i in range(len(data)):
            if i & 1:
                sample_data.append((i // 2 + 1, data[i].text, self._problem_id, False))
            else:
                sample_data.append((i // 2 + 1, data[i].text, self._problem_id, True))

        assert(len(data) % 2 == 0, 'Internal error: Number of sample input '
        ' is not equal to number of sample output')
        with concurrent.futures.ProcessPoolExecutor(max_workers=4) as executor:
            executor.map(write_samples, sample_data)
        print(_color_green(f'Generate {len(sample_data) // 2} sample(s) to {self._problem_id}'))



    cdef _act(self):
        print(f'Problem is {self._problem_id}')
        os.makedirs(self._problem_id, exist_ok=True)
        self._gen_samples()

    

cdef class Test(Action):
    def __cinit__(self):
        pass

    cdef _act(self):
        pass

cdef class Submit(Action):
    cdef str ac_icon
    cdef str rj_icon
    cdef str sk_icon

    def __cinit__(self):
        self.ac_icon = ':heavy_check_mark:'
        self.rj_icon = ':heavy_multiplication_x:'
        self.sk_icon = ':white_medium_square:'

    cdef bool_t is_finished(self, result, str status):    
        cdef int tot_res = len(result)
        cdef int ac_ct = 0
        cdef bool_t is_ac = True
        rejected = False
        for res in result:
            _class = res.get('class', None)
            if _class:
                if _class[0] == 'accepted':
                    ac_ct += 1
                else: # rejected
                    rejected = True
                    is_ac = False
                    break
        res = [self.ac_icon] * ac_ct

        if rejected:
            res.append(self.rj_icon)
        while len(res) < tot_res:
            res.append(self.sk_icon)

        cdef bool_t finished
        if rejected:
            finished = True
        else:
            finished = ac_ct == tot_res

        if not finished:
            status = _color_cyan(status)
        elif is_ac:
            status = _color_green(status)
        else:
            if status == 'Running': # status text not updated, lets try again
                return False
            status = _color_red(status)

        sys.stdout.write(f"Submission result: {status.center(20)} |  Test case status: {emoji.emojize(' '.join(res))}\r")
        sys.stdout.flush()
        return finished
        


    cdef _render_result(self, str submission_url_ret):
        time.sleep(1)
        # Display result
        self.login()
        page = requests.get(submission_url_ret, cookies=self.cookies, headers=_HEADERS)
        soup = BeautifulSoup(page.content, 'html.parser')
        submission_data = soup.find('div', class_='testcases')
        submission_ret = submission_data.find_all('span')
        status_ret = soup.find('td', class_='status middle').find('span')
        cdef int time_out = 20
        cdef float cur_time = 0
        while cur_time < time_out and not self.is_finished(submission_ret, status_ret.text):
            self.login()
            page = requests.get(submission_url_ret, cookies=self.cookies, headers=_HEADERS)
            soup = BeautifulSoup(page.content, 'html.parser')
            submission_data = soup.find('div', class_='testcases')
            tc_up = submission_data != None
            submission_ret = submission_data.find_all('span')
            status_ret = soup.find('td', class_='status middle').find('span')
            time.sleep(0.4)
            cur_time += 0.4
        print('\n', flush=True)

    
        

    cdef _act(self):
        cdef str problem_id = os.path.basename(os.getcwd())
        cdef str filename = f'{problem_id}.cpp'
        data = {'submit': 'true',
            'submit_ctr': 2,
            'language': 'C++',
            'mainclass': '',
            'problem': problem_id,
            'tag': '',
            'script': 'true'}
        files = []
        with open(filename) as sub_file:
            files.append(('sub_file[]',
                              (os.path.basename(filename),
                               sub_file.read(),
                               'application/octet-stream')))
        cdef str submit_url = self.get_url('submissionurl', 'submit')
        self.login()
        ret = requests.post(submit_url, data=data, files=files, 
            cookies=self.cookies, headers=_HEADERS)

        cdef str err
        if ret.status_code != 200:
            if ret.status_code == 403:
                err = 'Access denied (403)'
            elif ret.status_code == 404:
                err = 'Incorrect submit URL (404)'
            else:
                err = f'Status code: {ret.status_code}'
            raise RuntimeError(f'Submission failed: {err}')
        cdef str submissions_url = self.get_url('submissionsurl', 'submissions')
        submit_response = ret.content.decode('utf-8').replace('<br />', '\n')
        submission_id = re.search(r'Submission ID: (\d+)', submit_response).group(1)
        print(_color_green(f'Submission successful'))
        cdef str submission_url_ret = f'{submissions_url}/{submission_id}' 
        self._render_result(submission_url_ret)


cdef object map_key_to_class = {
    'gen': Gen,
    'test': Test,
    'submit': Submit
} 
cdef Action _arg_parse_wrapper(args: List[str]):
    if len(args) == 0:
        raise ValueError(f'No command provided to kt')
    if args[0] not in map_key_to_class:
        raise ValueError(f'first argument should be one of {map_key_to_class.keys()}')
    return map_key_to_class[args[0]](*args[1:])


def arg_parse(args: List[str]):
    return _arg_parse_wrapper(args)

def color_red(str text):
    return _color_red(text)
