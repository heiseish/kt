from ..version import version
from ..base import Action
from ..logger import color_cyan, log

__all__ = ['Version']


class Version(Action):
    def _act(self) -> None:
        log(f'Current version: {color_cyan(version)}')
