from kttool.version import version
from kttool.base import Action
from kttool.logger import color_cyan, log

class Version(Action):
    def _act(self) -> None:
        log(f'Current version: {color_cyan(version)}')