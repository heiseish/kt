import webbrowser
from typing_extensions import final
from ..base import Action
from ..logger import log

__all__ = ['Open']


@final
class Open(Action):
    REQUIRED_CONFIG = True

    def _act(self) -> None:
        problem_url = self.get_problem_url()
        log(f'Openning {problem_url}')
        webbrowser.open(problem_url)
