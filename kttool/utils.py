from collections import namedtuple
from pathlib import Path
import signal
import subprocess
import sys
from typing import NoReturn, Union
from dataclasses import dataclass
from .logger import color_cyan, log_green

__test_subprocesses = []

CATCH_PHRASE = 'Great is the art of beginning, but greater is the art of ending.'

def exit_gracefully(signum: signal.Signals, frame) -> NoReturn:
    global test_subprocesses
    original_sigint = signal.getsignal(signal.SIGINT)
    # restore the original signal handler as otherwise evil things will happen
    # in raw_input when CTRL+C is pressed, and our signal handler is not re-entrant
    signal.signal(signal.SIGINT, original_sigint)
    for sp in __test_subprocesses:
        try:
            sp.kill()
        except:
            pass
    log_green(CATCH_PHRASE)
    sys.exit(1)

def register_subprocess(p: subprocess.Popen):
    __test_subprocesses.append(p)


def ask_with_default(qu: str,  default_val: str = '') -> str:
    """ Print out `qu` to console and ask for input value from user
    If no input was provided by user, `default_val` will be returned instead

    Parameters
    ----------
    qu : str
        question to asked
    default_val : str, optional
        Default value to be used, by default ''

    Returns
    -------
    str
        string value as the response
    """
    qu = f'Please enter {color_cyan(qu)}'
    if default_val:
        qu = f'{qu} | Default value: {default_val}\n'
    ret = input(qu)
    if not ret:
        return default_val
    return ret

def make_list_equal(
    lhs: list, 
    rhs: list, 
    pad_element: str = ''
) -> None:
    """ Make two vector of string equation in length by padding with `pad_element`

    Parameters
    ----------
    lhs : list
        2 vectors of string to be made equal in length
    rhs : list
        2 vectors of string to be made equal in length
    pad_element : str, optional
        string to fill the shorter vector, by default ''
    """
    delta_size = abs(len(lhs) - len(rhs))
    delta_list = [ pad_element ] * delta_size
    if len(lhs) < len(rhs):
        lhs.extend(delta_list)
    else:
        rhs.extend(delta_list)


KATTIS_RC_URL = 'https://open.kattis.com/download/kattisrc'
HEADERS = {'User-Agent': 'kt'}

PLanguage = namedtuple('ProgrammingLanguage', 
    ['alias', 'extension', 'full_name', 'pre_script', 'script', 'post_script']
)


MAP_TEMPLATE_TO_PLANG = {
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
