from typing import List
from .actions.gen import Gen
from .actions.test import Test
from .actions.submit import Submit
from .actions.config import Config
from .actions.open import Open
from .actions.version import Version
from .actions.update import Update
from .base import Action

map_key_to_class = {
    'gen': Gen,
    'test': Test,
    'submit': Submit,
    'config': Config,
    'open': Open,
    'version': Version,
    'update': Update
}


def arg_parse(args: List[str]) -> Action:
    ''' Generate an appropriate command class based on user command stirng '''
    if len(args) == 0:
        raise ValueError(f'No command provided to kt')
    if args[0] not in map_key_to_class:
        raise ValueError(
            f'First argument should be one of {list(map_key_to_class.keys())}'
        )
    return map_key_to_class[args[0]](*args[1:])
