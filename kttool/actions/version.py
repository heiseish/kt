from ..version import version
from ..base import Action
from ..logger import color_cyan, log
from typing_extensions import final

__all__ = ['Version']


@final
class Version(Action):
    """Usage: kt version

    Print out the version of kttool
    """
    def _act(self) -> None:
        log(f'Current version: {color_cyan(version)}')
