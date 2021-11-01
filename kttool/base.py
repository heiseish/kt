from configparser import ConfigParser, NoOptionError
import abc
from pathlib import Path
from typing import Any, Dict, List, Optional
import requests
import os
from src.logger import color_green, log, log_cyan, log_red
import json
from src.utils import HEADERS, KATTIS_RC_URL, MAP_TEMPLATE_TO_PLANG, PLanguage


class ConfigError(Exception):
    pass


def require_login(fn):
    def inner(self: 'Action', *args, **kwargs):
        self.login()
        return fn(self, *args, **kwargs)
    return inner

class Action(abc.ABC):
    ''' 
    Base class for handle general command.
    Handle loading up .kattisrc config file
    '''
    REQUIRED_CONFIG = False

    cwd: Path
    config_path: Path
    cfg: Optional[ConfigParser]
    cookies: Any
    kt_config: Path

    file_name: Optional[Path] 
    lang: Optional[str] 
    pre_script: Optional[str]
    script: Optional[str] 
    post_script: Optional[str] 



    __slots__ = 'cwd', 'config_path', 'cfg', 'cookies', 'kt_config', 'file_name', 'lang', \
        'pre_script', 'script', 'post_script'

    def __init__(self, *, cwd: Optional[Path] = None):
        self.config_path = Path.home() /  '.kattisrc' # kattis config file
        self.kt_config = Path.home() /  '.ktconfig' # kt tool file
        self.cfg = None
        self.cwd = cwd or Path().absolute()
        self.cookies = None

        self.file_name = None
        self.lang = None
        self.pre_script = None
        self.script = None
        self.post_script = None

    def get_url(self,  option: str,  default: str = '') -> str:
        """ Get appropriate urls from kattisrc file

        Parameters
        ----------
        option : str
            parameter to get from katticrc config file
        default : str, optional
            fallback value if option is not present, by default ''

        Returns
        -------
        str
            Full url path to the required attr
        """
        if self.cfg.has_option('kattis', option):
            return self.cfg.get('kattis', option)

        kattis_host = self.cfg.get('kattis', 'hostname')
        return f'https://{kattis_host}/{default}'


    def read_config_from_file(self) -> None:
        """ kttool deals with 2 config files:
        - kattisrc: provided by official kattis website, provide domain name and general urls
        - ktconfig: handle templates by kttool

        Raises
        ------
        RuntimeError
            If config file is invalid
        ConfigError
            If config file is invalid
        """

        # Initialize ktconfig file if file doesnt exist
        if not self.kt_config.is_file():
            with open(self.kt_config, 'w') as f:
                f.write('{}\n')

        self.cfg = ConfigParser()
        if not self.config_path.is_file():
            raise RuntimeError(f'No valid config file at {self.config_path}. '
            f'Please download it at {KATTIS_RC_URL}')

        self.cfg.read(self.config_path)
        username = self.cfg.get('user', 'username')
        password = token = None
        try:
            password = self.cfg.get('user', 'password')
        except NoOptionError:
            pass
        try:
            token = self.cfg.get('user', 'token')
        except NoOptionError:
            pass
        if password is None and token is None:
            raise ConfigError('''\
        Your .kattisrc file appears corrupted. It must provide a token (or a
        KATTIS password).
        Please download a new .kattisrc file''')
        log(f'Username: {color_green(username)}')


    def login(self) -> None:
        """ Try to login and obtain cookies from succesful signin

        Raises
        ------
        RuntimeError
            If login fails
        """


        username = self.cfg.get('user', 'username')
        password = token = ''
        try:
            password = self.cfg.get('user', 'password')
        except NoOptionError:
            pass
        try:
            token = self.cfg.get('user', 'token')
        except NoOptionError:
            pass
        login_url = self.get_url('loginurl', 'login')
        login_args = {'user': username, 'script': 'true'}
        if password:
            login_args['password'] = password
        if token:
            login_args['token'] = token
        login_reply = self.request_post(login_url, data=login_args)
        
        if not login_reply.status_code == 200:
            if login_reply.status_code == 403:
                err = 'Incorrect username or password/token (403)'
            elif login_reply.status_code == 404:
                err = 'Incorrect login URL (404)'
            else:
                err = f'Status code: {login_reply.status_code}'
            raise RuntimeError(f'Login failed. {err}')
        self.cookies = login_reply.cookies

    def get_problem_id(self) -> str:
        # Assuming user is in the folder with the name of the problem id
        return self.cwd.name 

    def request_get(self, uri: str) -> requests.Response:
        return requests.get(uri, cookies=self.cookies, headers=HEADERS)


    def request_post(self, uri: str, *args, **kwargs) -> requests.Response:
        return requests.post(uri, *args, **kwargs, cookies=self.cookies, headers=HEADERS)

    @require_login
    def get_problem_url(self) -> str:
        domain = f"https://{self.get_url('hostname')}"
        problem_id = self.get_problem_id()

        return os.path.join(
            domain,
            'problems',
            problem_id
        )

    def detect_file_name(self) -> None:
        """ Confirm the executable file if there is multiple files that are runnable in current folder

        Raises
        ------
        RuntimeError
            If no executable code detected
        """
        acceptable_file_ext: Dict[str, PLanguage] = {}
        opt = 0
        i = 0
        existed_templates = self.load_kt_config()
        
        for k in existed_templates.keys():
            acceptable_file_ext[MAP_TEMPLATE_TO_PLANG[k].extension] = MAP_TEMPLATE_TO_PLANG[k]

        files = [x for x in self.cwd.iterdir() if x.is_file()]
        runnable_files: List[Path] = []
        for f in files:
            if f.suffix[1:] in acceptable_file_ext:
                runnable_files.append(f)
        
        if not runnable_files:
            raise RuntimeError('Not executable code file detected')
        
        if len(runnable_files) > 1:
            log_cyan('Choose a file to run')
            for i in range(len(runnable_files)):
                log(f'  {i}: {runnable_files[i].file_name}')
            opt = int(input())
            assert 0 <= opt < len(runnable_files), 'Invalid option chosen'

        
        self.file_name = runnable_files[opt]
        alias = acceptable_file_ext[runnable_files[opt].suffix[1:]].alias
        self.lang = acceptable_file_ext[runnable_files[opt].suffix[1:]].full_name

        file_name = self.file_name.stem
        self.pre_script = existed_templates.get(alias, {}).get('pre_script').replace('$%file%$', file_name)
        self.script = existed_templates.get(alias, {}).get('script').replace('$%file%$', file_name)
        self.post_script = existed_templates.get(alias, {}).get('post_script').replace('$%file%$', file_name)


    def load_kt_config(self) -> dict:
        if not self.kt_config.is_file():
            with open(self.kt_config, 'w+') as f:
                json.dump({}, f)

        try:
            with open(self.kt_config) as f:
                return json.load(f)
        except:
            log_red('kattis config maybe corrupted, resetting..')

        with open(self.kt_config, 'w+') as f:
            json.dump({}, f)
        return {}

    @abc.abstractmethod
    def _act(self) -> None:
        raise NotImplementedError()

    def act(self) -> None:
        ''' Python wrapper function to call cython private method _act
        '''
        if self.REQUIRED_CONFIG:
            self.read_config_from_file()
        self._act()
