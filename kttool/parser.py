from __future__ import annotations

from typing import List, Type
from .actions.gen import Gen
from .actions.test import Test
from .actions.submit import Submit
from .actions.config import Config
from .actions.open import Open
from .actions.version import Version
from .actions.update import Update
from .actions.surprise import Surprise
from .base import Action
from .logger import log, log_red

map_key_to_class = {
    'gen': Gen,
    'test': Test,
    'submit': Submit,
    'config': Config,
    'open': Open,
    'version': Version,
    'update': Update,
    'surprise': Surprise,
}

action_with_aliases = {
    **map_key_to_class,
    'g': Gen,
    't': Test,
    's': Submit,
    'c': Config,
    'o': Open,
    'v': Version,
    'u': Update,
    'r': Surprise,
    'random': Surprise,
}


def _is_help(args: List[str]) -> bool:
    return any(x in args for x in {'-h', '--help', 'help'})


def _print_help(klass: Type[Action]) -> None:
    log(klass.__doc__)


def arg_parse(args: List[str]) -> None | Action:
    ''' Generate an appropriate command class based on user command stirng '''
    if len(args) == 0:
        raise ValueError(f'No command provided to kt')
    if args[0] not in action_with_aliases:
        raise ValueError(
            f'First argument should be one of {list(map_key_to_class.keys())}'
        )
    klass = action_with_aliases[args[0]]
    if _is_help(args[1:]):
        return _print_help(klass)

    try:
        return klass(*args[1:])
    except:
        log_red('Invalid usage')
        return _print_help(klass)
