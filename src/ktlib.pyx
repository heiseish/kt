# cython: language_level=3, boundscheck=False, cdivision=True, wraparound=False
# distutils: language=c++
import sys
from pathlib import Path
import requests
import os
import re
import time
import shutil
from bs4 import BeautifulSoup
import multiprocessing
import concurrent.futures
from reprint import output
import emoji
from html.parser import HTMLParser
from collections import namedtuple
from subprocess import Popen, PIPE
import subprocess
import json
import shlex
from resource import *
import psutil
import configparser
import webbrowser
import signal

cimport cython
from libcpp.vector cimport vector
from libcpp cimport bool as bool_t
from libc.stdio cimport FILE, fopen, fclose, fflush
from .version import version
__all__ = [
    'arg_parse',
    'color_red',
    'color_green',
    'exit_gracefully'
]

# -------------- Global varible ----------------
DEF _KATTIS_RC_URL = 'https://open.kattis.com/download/kattisrc'
cdef object _HEADERS = {'User-Agent': 'kt'}

DEF _PYPI_PACKAGE_INFO = 'https://pypi.org/pypi/kttool/json'
cdef list test_subprocesses = []
# global structs
PLanguage = namedtuple('ProgrammingLanguage', 
    ['alias', 'extension', 'full_name', 'pre_script', 'script', 'post_script']
)

cdef class ConfigError(Exception):
    pass

cdef dict map_template_to_plang = {
    'c': PLanguage('c', 'c','C', 
        'gcc $%file%$.c -o $%file%$.out',
        './$%file%$.out',
        'rm $%file%$.out'
    ),
    'cpp': PLanguage('cpp', 'cpp', 'C++',
        'g++ -std=c++14 -D_GLIBCXX_DEBUG -D_GLIBCXX_DEBUG_PEDANTIC -O3 $%file%$.cpp -o $%file%$.out',
        './$%file%$.out',
        'rm $%file%$.out'
    ),
    'cc': PLanguage('cc', 'cc', 'C++', 
        'g++ -std=c++14 -D_GLIBCXX_DEBUG -D_GLIBCXX_DEBUG_PEDANTIC -O3 $%file%$.cc -o $%file%$.out',
        './$%file%$.out',
        'rm $%file%$.out'
    ),
    'go': PLanguage('go', 'go', 'Go', 
        'go build -o $%file%$',
        './$%file%$',
        'rm $%file%$'
    ),
    'java': PLanguage('java', 'java', 'Java', 
        'javac *.java',
        './$%file%$',
        'rm $%file%$'
    ),
    'js': PLanguage('js', 'js', 'JavaScript', 
        '',
        'node $%file%$.js',
        ''
    ),
    'rs': PLanguage('rs', 'rs', 'Rust', 
        'rustc $%file%$.rs',
        './$%file%$',
        'rm $%file%$'
    ),
    'py2': PLanguage('py2', 'py', 'Python 2', 
        '',
        'python2 $%file%$.py',
        ''
    ),
    'py3': PLanguage('py3', 'py', 'Python 3', 
        '',
        'python3 $%file%$.py',
        ''
    )
}
# -------------- Color for formatting ----------------
DEF BOLD_SEQ = '\033[1m'
DEF RESET_SEQ = '\033[0m'
DEF BLACK = '\033[6;90m'
DEF RED = '\033[6;91m'
DEF GREEN = '\033[6;92m'
DEF YELLOW = '\033[6;93m'
DEF BLUE = '\033[6;94m'
DEF MAGENTA = '\033[6;95m'
DEF CYAN = '\033[6;96m'
DEF WHITE = '\033[6;97m'

cpdef str color_cyan(str text):
    return f'{CYAN}{text}{RESET_SEQ}'


cpdef str color_green(str text):
    return f'{GREEN}{text}{RESET_SEQ}'


cpdef str color_red(str text):
    return f'{RED}{text}{RESET_SEQ}'

log = print
# -------------- Utility functions ----------------
cdef str ask_with_default(str qu, str default_val=''):
    ''' Print out `qu` to console and ask for input value from user
    If no input was provided by user, `default_val` will be returned instead
    Args:
    - qu:  question to asked
    - default_val: Default value to be used
    Returns:
    - string value as the response
    '''
    qu = f'Please enter {color_cyan(qu)}'
    if default_val:
        qu = f'{qu} | Default value: {default_val}\n'
    cdef str ret = input(qu)
    if not ret:
        return default_val
    return ret

cdef void make_list_equal(
    list lhs, 
    list rhs, 
    str pad_element = ''
) except *:
    ''' Make two vector of string equation in length by padding with `pad_element`
    Args:
    - lhs, rhs: 2 vectors of string to be made equal in length
    - pad_element: string to fill the shorter vector
    '''
    cdef int delta_size = abs(len(lhs) - len(rhs))
    cdef list delta_list = [ pad_element ] * delta_size
    if len(lhs) < len(rhs):
        lhs.extend(delta_list)
    else:
        rhs.extend(delta_list)

# -------------- Core functions/classes ----------------
cdef class Action:
    cdef:
        object config_path
        object cfg
        object cookies
        object kt_config
    ''' Base class for handle general command.
    Handle loading up .kattisrc config file
    '''
    def __cinit__(self):
        self.config_path = Path.home() /  '.kattisrc' # kattis config file
        self.kt_config = Path.home() /  '.ktconfig' # kt tool file
        self.cfg = None

    cdef str get_url(self, str option, str default = '') :
        ''' Get appropriate urls from kattisrc file
        Args:
        - option: parameter to get from katticrc config file
        - default: fallback value if option is not present
        Returns:
        - Full url path to the required attr
        '''
        cdef str kattis_host
        if self.cfg.has_option('kattis', option):
            return self.cfg.get('kattis', option)

        kattis_host = self.cfg.get('kattis', 'hostname')
        return f'https://{kattis_host}/{default}'


    cdef void read_config_from_file(self) except *:
        ''' kttool deals with 2 config files:
        - kattisrc: provided by official kattis website, provide domain name and general urls
        - ktconfig: handle templates by kttool
        '''
        # Initialize ktconfig file if file doesnt exist
        if not self.kt_config.is_file():
            with open(self.kt_config, 'w') as f:
                f.write('{}\n')

        self.cfg = configparser.ConfigParser()
        if not self.config_path.is_file():
            raise RuntimeError(f'No valid config file at {self.config_path}. '
            f'Please download it at {_KATTIS_RC_URL}')

        self.cfg.read(self.config_path)
        cdef str username = self.cfg.get('user', 'username')
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
        print(f'Username: {color_green(username)}')


    cdef void login(self) except *:
        ''' Try to login and obtain cookies from succesful signin
        '''
        cdef:
            str login_url
            str err
            str username
            str password

        username = self.cfg.get('user', 'username')
        password = token = ''
        try:
            password = self.cfg.get('user', 'password')
        except configparser.NoOptionError:
            pass
        try:
            token = self.cfg.get('user', 'token')
        except configparser.NoOptionError:
            pass
        login_url = self.get_url('loginurl', 'login')
        login_args = {'user': username, 'script': 'true'}
        if password:
            login_args['password'] = password
        if token:
            login_args['token'] = token
        login_reply = requests.post(login_url, data=login_args, headers=_HEADERS)
        
        if not login_reply.status_code == 200:
            if login_reply.status_code == 403:
                err = 'Incorrect username or password/token (403)'
            elif login_reply.status_code == 404:
                err = 'Incorrect login URL (404)'
            else:
                err = f'Status code: {login_reply.status_code}'
            raise RuntimeError(f'Login failed. {err}')
        self.cookies = login_reply.cookies

    cdef str get_problem_id(self):
        # Assuming user is in the folder with the name of the problem id
        return Path.cwd().name 

    cdef str get_problem_url(self):
        cdef:
            str domain = f"https://{self.get_url('hostname')}"
            str problem_id = self.get_problem_id()

        return os.path.join(
            domain,
            'problems',
            problem_id
        )


    cdef void _act(self) except *:
        raise NotImplementedError()

    cpdef void act(self) except *:
        ''' Python wrapper function to call cython private method _act
        '''
        self.read_config_from_file()
        self._act()

@cython.final
cdef class SampleData:
    cdef:
        str problem_id
        bint is_in
        str sample_id
        str data
    
    def __cinit__(self, str problem_id='', str data='', bint is_in=True, str sample_id=''):
        self.problem_id = problem_id
        self.is_in = is_in
        self.sample_id = sample_id
        self.data = data


cpdef void write_samples(SampleData sample_data) except *:
    ''' Write input/output sample to file. This is used for multiprocess pool to generate input/output files
    Args:
    - sample_data: a tuple representing index, string data, problem id and a boolean declaring whether current
    file is input (False if the file is output)
    '''
    cdef:
        str file_name_prefix = 'in' if sample_data.is_in else 'ans'
        str file_name = f'{sample_data.problem_id}/{file_name_prefix}{sample_data.sample_id}.txt'

    with open(file_name, 'w+') as f:
        f.write(sample_data.data)


@cython.final
cdef class Gen(Action):
    ''' Handle `gen` command for kt_tool '''
    cdef:
        str _problem_id
        str _url 
        
    ''' Handle `gen` command for kt_tool '''
    def __cinit__(self, str problem_id):
        self._problem_id = problem_id
        self._url = ''
    
    cdef void _gen_samples(self) except *:
        ''' Generate sample input file for `self._problem_id`
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
        '''
        cdef:
            str domain = f"https://{self.get_url('hostname')}"
            dict template_file = {}
            list sample_data = []
            object data
            object soup
            object page
            size_t i = 0
            str k
            dict template


        self.login()
        self._url = self.get_problem_url()
        page = requests.get(self._url, cookies=self.cookies, headers=_HEADERS)
        soup = BeautifulSoup(page.content, 'html.parser')
        data = soup.find_all('pre')

        for i in range(len(data)):
            if i & 1:
                sample_data.append(SampleData(sample_id=i // 2 + 1, data=data[i].text, problem_id=self._problem_id, is_in=False))
            else:
                sample_data.append(SampleData(sample_id=i // 2 + 1, data=data[i].text, problem_id=self._problem_id, is_in=True))

        assert len(data) % 2 == 0, 'Internal error: Number of sample input '\
            ' is not equal to number of sample output'

        with concurrent.futures.ProcessPoolExecutor(max_workers=4) as executor:
            executor.map(write_samples, sample_data)

        log(color_green(f'Generate {len(sample_data) // 2} sample(s) to {self._problem_id}'))
        if not os.path.exists(self.kt_config):
            log(color_red('.ktconfig file has not been set up so no template was generated. '
            'Please use `kt config` to set up a template file'))
            return

        
        with open(self.kt_config, 'r') as f:
            template_file = json.load(f)

        for k, template in template_file.items():
            if template.get('default', False):
                shutil.copyfile(template.get('path'), f'{self._problem_id}/{self._problem_id}.{map_template_to_plang[k].extension}')
                log(color_green('Template file has been generated'))
                return
        log(color_red(f'No default template detected in {self.kt_config}'))

    cdef void _act(self) except *:
        log(f'Problem is {self._problem_id}')
        cdef object problem_dir = Path.cwd() / self._problem_id
        problem_dir.mkdir(parents=True, exist_ok=True)
        self._gen_samples()
    

cdef tuple compare_entity(str lhs, str rhs):
    if lhs == rhs:
        return True, f'{lhs} '
    return False, f'{color_red(lhs)}{color_green(rhs)} '


@cython.final
cdef class RunnableFile:
    cdef:
        str ext
        str problem_id
        str file_name #Path

    def __cinit__(self, str problem_id, str ext, object file_name):
        self.problem_id = problem_id
        self.ext = ext
        self.file_name = file_name


@cython.final
cdef class Test(Action):
    cdef:
        str file_name
        str pre_script
        str script
        str post_script
        str lang

    cdef void detect_file_name(self) except *:
        ''' Confirm the executable file if there is multiple files that are runnable in current folder
        '''
        cdef:
            dict existed_templates = {}
            dict acceptable_file_ext = {}
            str alias
            str res
            int opt = 0
            list parts
            list runnable_files
            list files
            size_t i = 0
            str k
            object x, f

        with open(self.kt_config) as f:
            existed_templates = json.load(f)
        
        for k in existed_templates.keys():
            acceptable_file_ext[map_template_to_plang[k].extension] = map_template_to_plang[k]

        files = [x for x in Path('.').iterdir() if x.is_file()]
        runnable_files = []
        for f in files:
            parts = str(f).split('.')
            if len(parts) <= 1:
                continue
            if parts[1] in acceptable_file_ext:
                runnable_files.append(RunnableFile(
                    problem_id=parts[0], 
                    ext=parts[1], 
                    file_name=str(f)
                ))
        
        if len(runnable_files) == 0:
            raise RuntimeError('Not executable code file detected')
        
        if len(runnable_files) > 1:
            log(color_cyan('Choose a file to run'))
            for i in range(len(runnable_files)):
                log(f'  {i}: {runnable_files[i].file_name}')
            opt = int(input())
            assert 0 <= opt < len(runnable_files), 'Invalid option chosen'

        
        self.file_name = runnable_files[opt].problem_id
        alias = acceptable_file_ext[runnable_files[opt].ext].alias
        self.lang = acceptable_file_ext[runnable_files[opt].ext].full_name
        self.pre_script = existed_templates.get(alias, {}).get('pre_script').replace('$%file%$', self.file_name)
        self.script = existed_templates.get(alias, {}).get('script').replace('$%file%$', self.file_name)
        self.post_script = existed_templates.get(alias, {}).get('post_script').replace('$%file%$', self.file_name)


    cdef void _act(self) except *:
        ''' Run the executable file against sample input and output files present in the folder
        The sample files will only be recognized if the conditions hold:
        - Naming style should be in{idx}.txt and ans{txt}.txt
        - for in{idx}.txt, there must exist a ans{idx}.txt with the same `idx`
        '''
        cdef:
            list input_files, output_files, usable_samples
            object x, input_file, output_file


        self.detect_file_name()
        input_files = [x for x in Path('.').iterdir() if x.is_file() and str(x).startswith('in')]
        output_files = [x for x in Path('.').iterdir() if x.is_file() and str(x).startswith('ans')]
        usable_samples = []
        
        # Get sample files that match the condition
        Sample = namedtuple('Sample', 
            ['index', 'input_file', 'output_file']
        )
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
        usable_samples = sorted(usable_samples, key=lambda x: x.index)
        # run test
        log(f'Problem ID : {color_cyan(self.get_problem_id())}')
        log(f'Lanuage    : {self.lang}')
        if self.pre_script:
            subprocess.check_call(shlex.split(self.pre_script))


        cdef:
            double mem_used
            long rusage_denom = 1 << 20
            bint is_ac, is_good
            list actual = [], expected = [], diff = []
            list raw_input
            object proc # process 
            double start_time, taken
            str raw_output
            list ith_line_exp, ith_line_actual
            int i, j
            str current_diff, now_diff

        for sample in usable_samples:
            is_ac = True
            actual.clear()
            expected.clear()
            diff.clear()
            try:
                with open(sample.output_file, 'r') as f:
                    expected = [l.strip(" \n") for l in f.readlines()]
                with open(sample.input_file, 'rb') as f:    
                    raw_input = f.read()

                p = Popen([self.script, '-'], stdin=PIPE, stdout=PIPE, shell=False, 
                    preexec_fn=os.setsid)
                test_subprocesses.append(p)
                proc = psutil.Process(p.pid)
                mem_used = proc.memory_info().rss / rusage_denom
                start_time = time.perf_counter()
                raw_output = p.communicate(raw_input)[0].decode()
                p.wait()
                taken = time.perf_counter()  - start_time
                actual = [z.strip(" \n") for z in raw_output.split('\n')]
                make_list_equal(actual, expected)

                for i in range(len(expected)):
                    ''' Compare the values line by line
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
                    log(raw_input)
                    log(color_cyan('--- Diff ---'))
                    for i in range(len(diff)):
                        log(diff[i])

            except Exception as e:
                log(color_red(f'Test case #{sample.index}: Runtime Error {e}'))

        if self.post_script:
            subprocess.check_call(shlex.split(self.post_script))

@cython.final
cdef class Submit(Action):
    '''Handle kt submit action to push the file to kattis website'''
    cdef:
        str ac_icon
        str rj_icon
        str sk_icon

        str file_name
        str lang
        str submission_id
        str problem_id

    def __cinit__(self):
        self.ac_icon = ':heavy_check_mark:'
        self.rj_icon = ':heavy_multiplication_x:'
        self.sk_icon = ':white_medium_square:'
        

    cdef bint is_finished(self, object output_lines, object result, str status, str run_time) except? -1: 
        ''' Judge whether the result and status obtained from kattis submission
        page has indicated whether the solution judgement has been done
        Args:
        - output_lines console object to print multiple lines inline
        - result: List of object corresponding to the HTML component of test case on kattis submission
        page
        - status: Status obtained from kattis submission page
        - run_time: Time taken obtained from kattis submissione page
        '''   
        cdef:
            int tot_res = len(result)
            int ac_ct = 0
            bint is_ac = True
            bint rejected = False
            bint finished = False
            str _status = status

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
            if status == 'Running': # status text not updated, lets try again
                finished = False
            elif is_ac:
                _status = color_green(status)
            else:
                _status = color_red(status)

        output_lines['current time      '] = f"{time.strftime('%02l:%M%p %Z on %b %d, %Y')}"
        output_lines['language          '] = f'{self.lang}' 
        output_lines['problem id        '] = self.problem_id
        output_lines['running time      '] = f'{run_time}' 
        output_lines['submission id     '] = self.submission_id
        output_lines['submission result '] = f'{_status}'
        output_lines['test cases        '] = f"{emoji.emojize(' '.join(res))}"
        return finished
        


    cdef void _render_result(self, str submission_url_ret) except *:
        ''' Continuously polling for result from `submission_url_ret`
        Args:
        - submission_url_ret: url for the submission to be checked
        '''
        cdef:
            int time_out = 20
            double cur_time = 0
            str status_ret
            str runtime_ret
            bint done  = False


        with output(output_type='dict') as output_lines:
            while cur_time < time_out and not done:
                try:
                    self.login()
                    page = requests.get(submission_url_ret, cookies=self.cookies, headers=_HEADERS)
                    soup = BeautifulSoup(page.content, 'html.parser')
                    submission_data = soup.find('div', class_='testcases')
                    submission_ret = submission_data.find_all('span')
                    status_ret = soup.find('td', class_='status middle').find('span').text
                    runtime_ret = soup.find('td', class_='runtime middle').text
                    done = self.is_finished(output_lines, submission_ret, status_ret, runtime_ret)
                except Exception as e:
                    log(color_red(f'Internal error: {e}'))

                time.sleep(0.4)
                cur_time += 0.4


    cdef str detect_file_name(self):
        ''' Detect executable file to submit for kattis judge if there are multiple files
        that are executable based on user ktconfig file
        '''
        cdef:
            dict acceptable_file_ext = {}
            str alias
            int opt = 0, i
            int res_int
            str res
            list files, runnable_files
            object f

        for k in map_template_to_plang.keys():
            acceptable_file_ext[map_template_to_plang[k].extension] = map_template_to_plang[k]
        files = [f for f in Path().iterdir() if f.is_file()]
        runnable_files = []
        RunnableFile = namedtuple('RunnableFile',
            ['file_name', 'full_name', 'ext']
        )
        for f in files:
            parts = f.split('.')
            if len(parts) <= 1:
                continue
            if parts[1] in acceptable_file_ext:
                runnable_files.append(RunnableFile(parts[0], f, parts[1]))

        if len(runnable_files) == 0:
            raise RuntimeError('Not executable code file detected')

        if len(runnable_files) > 1:
            log(color_cyan('Choose a file:'))
            for i in range(len(runnable_files)):
                print(f'  {i}: {runnable_files[i].full_name}')
            res = input()
            opt = int(res)
            assert 0 <= opt < len(runnable_files), 'Invalid option chosen'
        self.problem_id = runnable_files[opt].file_name
        self.file_name = os.path.abspath(runnable_files[opt].full_name) 
        if runnable_files[opt].ext == 'py':
            res = input('Which python version you want to submit, 2 or 3?\n')
            res_int = int(res)
            assert 2 <= res_int <= 3, "Invalid option"
            self.lang = f'Python {res_int}'
        else:
            self.lang = acceptable_file_ext[runnable_files[opt].ext].full_name
            

    cdef void _act(self) except *:
        '''Submit the code file for kattis judge'''
        cdef:
            str err
            str submissions_url
            str submission_url_ret
            str submit_response
            str problem_id = self.get_problem_id()
            list files

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
                              (os.path.basename(self.file_name),
                               sub_file.read(),
                               'application/octet-stream')))
        submit_url = self.get_url('submissionurl', 'submit')
        self.login()
        ret = requests.post(submit_url, data=data, files=files, 
            cookies=self.cookies, headers=_HEADERS)
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
        log(color_green('Submission successful'))
        submission_url_ret  = f'{submissions_url}/{self.submission_id}' 
        self._render_result(submission_url_ret)


cdef class Config(Action):
    cdef add_template(self):
        cdef:
            str question = 'Which template would you like to add:\n'
            str temp
            dict selectable_lang = {}
            int idx = 1
            dict existed_templates = {}
            str res
            int ret
            dict options = {}

        log(color_green('Adapted from xalanq\'s cf tool'))
        log('''
Template will run 3 scripts in sequence when you run "kt test":
    - before_script   (execute once)
    - script          (execute the number of samples times)
    - after_script    (execute once)
You could set "before_script" or "after_script" to empty string, meaning not executing.
You have to run your program in "script" with standard input/output (no need to redirect).

You can insert some placeholders in your scripts. When execute a script,
cf will replace all placeholders by following rules:

$%path%$   Path to source file (Excluding $%full%$, e.g. "/home/user/")
$%full%$   Full name of source file (e.g. "a.cpp")
$%file%$   Name of source file (Excluding suffix, e.g. "a")
$%rand%$   Random string with 8 character (including "a-z" "0-9")
        ''')
        

        with open(self.kt_config) as f:
            existed_templates = json.load(f)

        for template_type, lang in map_template_to_plang.items():
            if template_type not in existed_templates:
                temp = f'{idx} ({lang.extension}): {lang.full_name}\n'
                question.append(temp)
                selectable_lang[idx] = (template_type, lang)
                idx += 1

        res = input(question)
        ret = int(res)
        assert 1 <= ret < idx, 'Invalid input'
        
        selected_lang = selectable_lang[ret][1]
        options['path'] = ask_with_default('Template path', f'~/template.{selected_lang.extension}')
        options['pre_script'] = ask_with_default('Pre-script', selected_lang.pre_script)
        options['script'] = ask_with_default('Script', selected_lang.script)
        options['post_script'] = ask_with_default('Post-script', selected_lang.post_script)
        options['default'] = False if existed_templates else True

        existed_templates[selected_lang.alias] = options
        with open(self.kt_config, 'w') as kt_config:
            json.dump(existed_templates, kt_config, indent=2)
        log(color_green('Yosh, your configuration has been saved'))


    cdef remove_template(self):
        ''' Remove a template from ktconfig file'''
        cdef:
            dict existed_templates = {}
            str res
            bint move_default

        with open(self.kt_config) as f:
            existed_templates = json.load(f)

        log(f'Which template would you like to {color_red("delete")} ? For eg cpp, cc, ...')
        for k, v in existed_templates.items():
            log(k)
        res = input()

        assert res in existed_templates, f'Invalid template chosen. Template {res} is not in ur config file'

        move_default = existed_templates[res]['default']
        existed_templates.pop(res, None)
        if existed_templates and move_default: # move default to the first key of template
            existed_templates[next(iter(existed_templates))] = True
        with open(self.kt_config, 'w') as kt_config:
            json.dump(existed_templates, kt_config, indent=2)

    cdef void update_default(self) except *:
        cdef:
            dict existed_templates = {}
            str res
            str default_key = ''

        with open(self.kt_config) as f:
            existed_templates = json.load(f)
        log(f'Which template would you like to gen as {color_cyan("default")} ? For eg cpp, cc, ...')
        
        for k, v in existed_templates.items():
            log(f'{k} {color_green("(default)") if v["default"] else ""}')
            if v["default"]:
                default_key = k
        res  = input()

        assert res in existed_templates, f'Invalid template chosen. Template {res} is not in ur config file'
        existed_templates[default_key]["default"] = False
        existed_templates[res]["default"] = True
        with open(self.kt_config, 'w') as kt_config:
            json.dump(existed_templates, kt_config, indent=2)
        log(color_green('Yosh, your configuration has been saved'))

    cdef void _act(self):
        cdef:
            str question = color_cyan('Select an option:\n')
            str res
            int opt
        question.append("""1: Add a template
2: Remove a template
3: Select a default template
""")
        res = input(question)
        opt = int(res)
        if opt == 1:
            self.add_template()
        elif opt == 2:
            self.remove_template()
        elif opt == 3:
            self.update_default()
        else:
            raise ValueError('Invalid option')

cdef class Open(Action):
    cdef void _act(self) except *:
        webbrowser.open(self.get_problem_url())

cdef class Version(Action):
    cdef void _act(self) except *:
        log(f'Current version: {color_cyan(version)}')

cdef class Update(Action):
    cdef void _act(self) except *:
        cdef:
            object pypi_info 
            list releases
            str current_latest_version

        pypi_info = requests.get(_PYPI_PACKAGE_INFO)
        releases = list(pypi_info.json()['releases'])
        if len(releases) == 0:
            log(color_red('Hmm seems like there is currently no pypi releases :-?'))
            return
        current_latest_version = releases.back()
        if current_latest_version != VERSION:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", "--no-cache-dir", f"kttool=={current_latest_version}"])
            log(f'Installed version {color_green(current_latest_version)} successfully!')
        else:
            log(f'You already have the {color_green("latest")} version!')


cdef dict map_key_to_class = {
    'gen': Gen,
    'test': Test,
    'submit': Submit,
    'config': Config,
    'open': Open,
    'version': Version,
    'update': Update
} 

cpdef Action arg_parse(list args):
    ''' Generate an appropriate command class based on user command stirng '''
    if len(args) == 0:
        raise ValueError(f'No command provided to kt')
    if args[0] not in map_key_to_class:
        raise ValueError(f'First argument should be one of {list(map_key_to_class.keys())}')
    return map_key_to_class[args[0]](*args[1:])


def exit_gracefully(signum, frame):
    original_sigint = signal.getsignal(signal.SIGINT)
    # restore the original signal handler as otherwise evil things will happen
    # in raw_input when CTRL+C is pressed, and our signal handler is not re-entrant
    signal.signal(signal.SIGINT, original_sigint)
    for sp in test_subprocesses:
        try:
            sp.kill()
        except:
            pass
    log(color_green('Great is the art of beginning, but greater is the art of ending.'))
    sys.exit(1)
    

    