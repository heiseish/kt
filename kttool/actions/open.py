from kttool.base import Action
import webbrowser

from kttool.logger import log

class Open(Action):
    REQUIRED_CONFIG = True

    def _act(self) -> None:
        log(f'Openning {self.get_problem_url()}')
        webbrowser.open(self.get_problem_url())