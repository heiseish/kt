from .context import supports_color

__all__ = [
    'color_cyan',
    'color_green',
    'color_red',
    'log',
    'log_green',
    'log_cyan',
    'log_red'
]

BOLD_SEQ = '\033[1m'
RESET_SEQ = '\033[0m'
BLACK = '\033[6;90m'
RED = '\033[6;91m'
GREEN = '\033[6;92m'
YELLOW = '\033[6;93m'
BLUE = '\033[6;94m'
MAGENTA = '\033[6;95m'
CYAN = '\033[6;96m'
WHITE = '\033[6;97m'

def color_cyan(text: str) -> str:
    if not supports_color:
        return text
    return f'{CYAN}{text}{RESET_SEQ}'


def color_green(text: str) -> str:
    if not supports_color:
        return text
    return f'{GREEN}{text}{RESET_SEQ}'


def color_red(text: str) -> str:
    if not supports_color:
        return text
    return f'{RED}{text}{RESET_SEQ}'


log = print

def log_green(*args, **kwargs) -> None:
    log(color_green(*args, **kwargs))


def log_cyan(*args, **kwargs) -> None:
    log(color_cyan(*args, **kwargs))


def log_red(*args, **kwargs) -> None:
    log(color_red(*args, **kwargs))