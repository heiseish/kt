#cython: language_level=3, c_str_type=unicode, c_str_encoding=utf8
import sys
from typing import List, Tuple
from libcpp.string cimport string
from libcpp.vector cimport vector
from libcpp cimport bool as bool_t
import requests
import os
import re
import time
import shutil
from bs4 import BeautifulSoup
import multiprocessing
import concurrent.futures
from reprint import output
from html.parser import HTMLParser
import emoji
from collections import namedtuple
import subprocess
from subprocess import Popen, PIPE
import json
import shlex
from resource import *
import psutil

if sys.version_info[0] >= 3:
    import configparser
else:
    import ConfigParser as configparser

__all__ = [
    'arg_parse',
    'color_red',
    'color_green'
]

PLanguage = namedtuple('ProgrammingLanguage', 
    ['alias', 'extension', 'full_name', 'pre_script', 'script', 'post_script']
)
_HEADERS = {'User-Agent': 'kt'}
cdef object map_template_to_plang = {
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

cdef str strike(str text):
    cdef str result = ''
    for c in text:
        result = result + c + '\u0336'
    return result

cdef class ConfigError(Exception):
    pass


cdef str ask_with_default(str qu, str default_val=''):
    qu = f'Please enter {_color_cyan(qu)}'
    if default_val:
        qu = f'{qu} | Default value: {default_val}\n'
    cdef str ret = input(qu)
    if not ret:
        return default_val
    return ret

cdef void make_list_equal(vector[string]& list1, vector[string]& list2, string pad_element = b''):
    while list1.size() < list2.size():
        list1.push_back(pad_element)
    while list2.size() < list1.size():
        list2.push_back(pad_element)

cdef class Action(object):
    cdef str config_path
    cdef object cfg
    cdef object cookies
    cdef str kt_config

    
    def __cinit__(self):
        self.config_path = os.path.join(os.getenv('HOME'), '.kattisrc')
        self.kt_config = os.path.join(os.getenv('HOME'), '.ktconfig')
        if not os.path.exists(self.kt_config):
            with open(self.kt_config, 'w') as f:
                f.write('{}\n')

    cdef str get_url(self, str option, str default):
        cdef str kattis_host
        if self.cfg.has_option('kattis', option):
            return self.cfg.get('kattis', option)
        else:
            kattis_host = self.cfg.get('kattis', 'hostname')
            return f'https://{kattis_host}/{default}'


    cdef read_config_from_file(self):
        ''' Read config from kattisrc file, which should be located at
        `$HOME/.kattisrc`
        '''
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
        print(f'Username: {_color_green(username)}')


    cdef login(self):
        ''' Try to login and obtain cookies from succesful signin
        '''
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

    cdef _act(self):
        raise NotImplementedError

    def act(self):
        self.read_config_from_file()
        self._act()


cdef void cwrite_samples(sample_data: Tuple[int, str, str, bool]):
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

        if not os.path.exists(self.kt_config):
            print(_color_red('kt_config file has not been set up so no template was generated. '
            'Please use `kt config` to set up a template file'))
            return

        cdef object template_file = {}
        with open(self.kt_config, 'r') as f:
            template_file = json.load(f)
        for k, template in template_file.items():
            if template.get('default', False):
                shutil.copyfile(template.get('path'), f'{self._problem_id}/{self._problem_id}.{map_template_to_plang[k].extension}')
                print(_color_green('Template file has been generated'))
                return
        print(_color_red(f'No default template detected in {self.kt_config}'))



    cdef _act(self):
        print(f'Problem is {self._problem_id}')
        os.makedirs(self._problem_id, exist_ok=True)
        self._gen_samples()
    

cdef class Test(Action):
    cdef str file_name
    cdef str pre_script
    cdef str script
    cdef str post_script
    cdef str lang

    cdef detect_file_name(self):
        cdef object existed_templates = {}
        cdef object acceptable_file_ext = {}
        with open(self.kt_config) as f:
            existed_templates = json.load(f)
        
        for k, v in existed_templates.items():
            acceptable_file_ext[map_template_to_plang[k].extension] = map_template_to_plang[k]

        files = [f for f in os.listdir('.') if os.path.isfile(f)]
        runnable_files = []
        for f in files:
            parts = f.split('.')
            if len(parts) <= 1:
                continue
            if  parts[1] in acceptable_file_ext:
                runnable_files.append((parts[0], f, parts[1]))
        cdef str alias
        if len(runnable_files) == 0:
            raise RuntimeError('Not executable code file detected')

        if len(runnable_files) == 1:
            self.file_name = runnable_files[0][0]
            alias = acceptable_file_ext[runnable_files[0][2]].alias
            self.lang = acceptable_file_ext[runnable_files[0][2]].full_name
            self.pre_script = existed_templates.get(alias, {}).get('pre_script').replace('$%file%$', self.file_name)
            self.script = existed_templates.get(alias, {}).get('script').replace('$%file%$', self.file_name)
            self.post_script = existed_templates.get(alias, {}).get('post_script').replace('$%file%$', self.file_name)
            return

        print(_color_cyan('Choose a file to run'))
        for i in range(len(runnable_files)):
            print(f'  {i}: {runnable_files[i][1]}')
        cdef str res = input()
        cdef int opt = int(res)
        assert 0 <= opt < len(runnable_files), 'Invalid option chosen'
        self.file_name = runnable_files[opt][0]
        alias = acceptable_file_ext[runnable_files[opt][2]].alias
        self.lang = acceptable_file_ext[runnable_files[opt][2]].full_name
        self.pre_script = existed_templates.get(alias, {}).get('pre_script').replace('$%file%$', self.file_name)
        self.script = existed_templates.get(alias, {}).get('script').replace('$%file%$', self.file_name)
        self.post_script = existed_templates.get(alias, {}).get('post_script').replace('$%file%$', self.file_name)


    cdef _act(self):
        self.detect_file_name()
        input_files = [f for f in os.listdir('.') if os.path.isfile(f) and f.startswith('in')]
        output_files = [f for f in os.listdir('.') if os.path.isfile(f) and f.startswith('ans')]
        usable_samples = []
        cdef int idx
        pattern = re.compile(r"\d+")
        for input_file in input_files:
            idx = int(pattern.search(input_file).group(0))
            for output_file in output_files:
                if idx == int(pattern.search(output_file).group(0)):
                    usable_samples.append((idx, input_file, output_file))
                    break
        usable_samples = sorted(usable_samples, key=lambda x: x[0])
        # run test
        cdef:
            float start_time
            float taken
            vector[string] actual
            vector[string] expected
            vector[string] diff
            vector[string] ith_line_exp
            vector[string] ith_line_actual
            string current_diff
            bool_t is_ac
            bytes raw_output
            str stderr_data_decoded
            string lhs
            string rhs
            string temp
            float mem_used
            long rusage_denom = 1024

        if sys.platform == 'darwin':
            rusage_denom = rusage_denom * rusage_denom

        print(f'Problem ID : {_color_cyan(os.path.basename(os.getcwd()))}')
        print(f'Lanuage    : {self.lang}')
        if self.pre_script:
            subprocess.check_call(shlex.split(self.pre_script))
        for sample in usable_samples:
            is_ac = True
            actual.clear()
            expected.clear()
            diff.clear()
            try:
                with open(sample[2], 'r') as f:
                    expected = [l.strip(" \n").encode('utf-8') for l in f.readlines()]
                with open(sample[1], 'rb') as f:
                    raw_input = f.read()

                p = Popen([self.script, '-'], stdin=PIPE, stdout=PIPE, stderr=PIPE, shell=True, 
                    preexec_fn=os.setsid)
                proc = psutil.Process(p.pid)
                mem_used = proc.memory_info().rss / rusage_denom
                start_time = time.perf_counter()
                raw_output, stderr_data = p.communicate(raw_input)
                taken = time.perf_counter()  - start_time

                stderr_data_decoded = stderr_data.decode('utf-8')
                if stderr_data_decoded:
                    print(stderr_data_decoded, file=sys.stderr)

                actual = [z.strip(" \n").encode('utf-8') for z in raw_output.decode('utf-8').split('\n')]

                make_list_equal(actual, expected)

                assert actual.size() == expected.size(), \
                    'Internal Error: Actual and expect list dont have the same length'
                diff.clear()
                for i in range(len(expected)):
                    ith_line_exp = [z.encode('utf-8') for z in expected[i].decode('utf-8').split(' ')]
                    ith_line_actual = [z.encode('utf-8') for z in actual[i].decode('utf-8').split(' ')]

                    make_list_equal(ith_line_exp, ith_line_actual)
                    assert ith_line_exp.size() == ith_line_actual.size(), \
                    'Internal Error: Actual and expect ith_line dont have the same length'
                    current_diff.clear()
                    for j in range(len(ith_line_exp)):
                        lhs = ith_line_exp[j]
                        rhs = ith_line_actual[j]
                        temp = f"{_color_red(strike(ith_line_actual[j].decode()))}{_color_green(ith_line_exp[j].decode())} ".encode('utf-8')
                        if lhs == rhs:
                            current_diff += lhs
                            current_diff.push_back(b' ')
                        else:
                            current_diff += temp
                            is_ac = False
                    diff.push_back(current_diff)
                if is_ac:
                    print(_color_green(f'Test Case #{sample[0]}: {"Accepted".ljust(13, " ")} ... {taken:.3f} s   {mem_used:.2f} Mb'))
                else:
                    print(_color_red(f'Test Case #{sample[0]}: {"Wrong Answer".ljust(13, " ")} ... {taken:.3f} s   {mem_used:.2f} Mb'))
                    print(_color_cyan('--- Input ---'))
                    print(raw_input.decode())
                    print(_color_cyan('--- Diff ---'))
                    for i in range(diff.size()):
                        print(diff[i].decode())

            except Exception as e:
                print(_color_red(f'Test case #{sample[0]}: Runtime Error {e}'))
        if self.post_script:
            subprocess.check_call(shlex.split(self.post_script))


cdef class Submit(Action):
    cdef str ac_icon
    cdef str rj_icon
    cdef str sk_icon

    cdef str file_name
    cdef str lang

    def __cinit__(self):
        self.ac_icon = ':heavy_check_mark:'
        self.rj_icon = ':heavy_multiplication_x:'
        self.sk_icon = ':white_medium_square:'
        

    cdef bool_t is_finished(self, object output_lines, result, str status):    
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

        if status == 'Compiling':
            return False
        if status == 'Compile Error':
            status = _color_red(status)
        elif not finished:
            status = _color_cyan(status)
        else:
            if status == 'Running': # status text not updated, lets try again
                finished = False
            elif is_ac:
                status = _color_green(status)
            else:
                status = _color_red(status)

        output_lines['Job              '] = 'Kattis submission'
        output_lines['Current time     '] = f"{time.strftime('%l:%M%p %Z on %b %d, %Y')}"
        output_lines['Language         '] = f'{self.lang}' 
        output_lines['Submission result'] = f'{status}'
        output_lines['Test cases status'] = f"{emoji.emojize(' '.join(res))}"
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
        with output(output_type='dict') as output_lines:
            while cur_time < time_out and not self.is_finished(output_lines, submission_ret, status_ret.text):
                self.login()
                page = requests.get(submission_url_ret, cookies=self.cookies, headers=_HEADERS)
                soup = BeautifulSoup(page.content, 'html.parser')
                submission_data = soup.find('div', class_='testcases')
                tc_up = submission_data != None
                submission_ret = submission_data.find_all('span')
                status_ret = soup.find('td', class_='status middle').find('span')
                time.sleep(0.4)
                cur_time += 0.4


    cdef detect_file_name(self):
        cdef object acceptable_file_ext = {}
        for k, v in map_template_to_plang.items():
            acceptable_file_ext[map_template_to_plang[k].extension] = map_template_to_plang[k]
        files = [f for f in os.listdir('.') if os.path.isfile(f)]
        runnable_files = []
        for f in files:
            parts = f.split('.')
            if len(parts) <= 1:
                continue
            if  parts[1] in acceptable_file_ext:
                runnable_files.append((parts[0], f, parts[1]))

        cdef str alias
        if len(runnable_files) == 0:
            raise RuntimeError('Not executable code file detected')

        cdef int opt = 0
        cdef int res_int
        cdef str res
        if len(runnable_files) > 1:
            print(_color_cyan('Choose a file to run'))
            for i in range(len(runnable_files)):
                print(f'  {i}: {runnable_files[i][1]}')
            res = input()
            opt = int(res)
            assert 0 <= opt < len(runnable_files), 'Invalid option chosen'

        self.file_name = os.path.abspath(runnable_files[opt][1]) 
        if runnable_files[opt][2] == 'py':
            res = input('Which python version you want to submit, 2 or 3?\n')
            res_int = int(res)
            assert 2 <= res_int <= 3, "Invalid option"
            self.lang = f'Python {res_int}'
        else:
            self.lang = acceptable_file_ext[runnable_files[opt][2]].full_name
            
    cdef _act(self):
        self.detect_file_name()
        cdef str problem_id = os.path.basename(os.getcwd())
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


cdef class Config(Action):
    cdef add_template(self):
        print(_color_green('Adapted from xalanq\'s cf tool'))
        print('''
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
        cdef str question = 'Which template would you like to add:\n'
        cdef object selectable_lang = {}
        cdef int idx = 1
        cdef object existed_templates = {}

        with open(self.kt_config) as f:
            existed_templates = json.load(f)

        for template_type, lang in map_template_to_plang.items():
            if template_type not in existed_templates:
                question += f'{idx} ({lang.extension}): {lang.full_name}\n'
                selectable_lang[idx] = (template_type, lang)
                idx += 1

        cdef str res = input(question)
        cdef int ret = int(res)
        assert 1 <= ret < idx, 'Invalid input'
        cdef object options = {}
        selected_lang = selectable_lang[ret][1]
        options['path'] = ask_with_default('Template path', f'~/template.{selected_lang.extension}')
        options['pre_script'] = ask_with_default('Pre-script', selected_lang.pre_script)
        options['script'] = ask_with_default('Script', selected_lang.script)
        options['post_script'] = ask_with_default('Post-script', selected_lang.post_script)
        options['default'] = False if existed_templates else True

        existed_templates[selected_lang.alias] = options
        with open(self.kt_config, 'w') as kt_config:
            json.dump(existed_templates, kt_config, indent=2)
        print(_color_green('Yosh, your configuration has been saved'))


    cdef remove_template(self):
        cdef object existed_templates = {}

        with open(self.kt_config) as f:
            existed_templates = json.load(f)

        print(f'Which template would you like to {_color_red("delete")} ? For eg cpp, cc, ...')
        for k, v in existed_templates.items():
            print(k)
        cdef str res = input()

        assert res in existed_templates, f'Invalid template chosen. Template {res} is not in ur config file'

        cdef bool_t move_default = existed_templates[res]['default']
        existed_templates.pop(res, None)
        if existed_templates and move_default: # move default to the first key of template
            existed_templates[next(iter(existed_templates))] = True
        with open(self.kt_config, 'w') as kt_config:
            json.dump(existed_templates, kt_config, indent=2)

    cdef update_default(self):
        cdef object existed_templates = {}

        with open(self.kt_config) as f:
            existed_templates = json.load(f)
        print(f'Which template would you like to gen as {_color_cyan("default")} ? For eg cpp, cc, ...')
        cdef str default_key = ''
        for k, v in existed_templates.items():
            print(f'{k} {_color_green("(default)") if v["default"] else ""}')
            if v["default"]:
                default_key = k

        cdef str res = input()

        assert res in existed_templates, f'Invalid template chosen. Template {res} is not in ur config file'
        existed_templates[default_key]["default"] = False
        existed_templates[res]["default"] = True
        with open(self.kt_config, 'w') as kt_config:
            json.dump(existed_templates, kt_config, indent=2)
        print(_color_green('Yosh, your configuration has been saved'))

    cdef _act(self):
        cdef str question = _color_cyan('Select an option:\n')
        question += """1: Add a template
2: Remove a template
3: Select a default template
"""
        cdef str res = input(question)
        cdef int opt = int(res)
        if opt == 1:
            self.add_template()
        elif opt == 2:
            self.remove_template()
        elif opt == 3:
            self.update_default()
        else:
            raise ValueError('Invalid option')



cdef object map_key_to_class = {
    'gen': Gen,
    'test': Test,
    'submit': Submit,
    'config': Config
} 

cdef Action _arg_parse_wrapper(args: List[str]):
    if len(args) == 0:
        raise ValueError(f'No command provided to kt')
    if args[0] not in map_key_to_class:
        raise ValueError(f'First argument should be one of {list(map_key_to_class.keys())}')
    return map_key_to_class[args[0]](*args[1:])


def arg_parse(args: List[str]):
    return _arg_parse_wrapper(args)

def color_green(str text):
    return _color_green(text)

def color_red(str text):
    return _color_red(text)
