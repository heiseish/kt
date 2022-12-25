from __future__ import annotations
from pathlib import Path
import webbrowser
from typing_extensions import final
from ..base import Action
from ..logger import log

__all__ = ['Open']


@final
class Open(Action):
    """Usage: kt open [problem_id]

    Open the default browser with the link to the full problem statement on Kattis. If no problem id is provided, the problem id wil be deduced using the 
    current directionary name
    
    Options
    --------
    problem_id: Kattis problem id
    """
    REQUIRED_CONFIG = True

    __slots__ = '_problem_id'

    def __init__(
        self, problem_id: None | str = None, *, cwd: None | Path = None
    ):
        super().__init__(cwd=cwd)
        self._problem_id = problem_id

    def _act(self) -> None:
        problem_url = self.get_problem_url(self._problem_id)
        log(f'Openning {problem_url}')
        webbrowser.open(problem_url)
