from __future__ import annotations
from ast import List
from dataclasses import dataclass
from pathlib import Path
import random
from .gen import Gen
from ..base import Action
from bs4 import BeautifulSoup
from typing_extensions import final

__all__ = ['Surprise']

DifficultyFixed = float
DifficultyRange = (float, float)


@final
@dataclass
class KattisProblem:
    id: str
    difficulty: DifficultyFixed | DifficultyRange


@final
class Surprise(Action):
    """Usage: kt surprise [lower_bound] [upperBound]

    Randomly retrieve a problem from Kattis whose difficulty belongs to the range
    Naturally lower_bound has to be <= upperbound

    Options
    --------
    lower_bound: lower range bound to randomize. Default is 0
    upper_bound: lower range bound to randomize. Default is 10
    """
    REQUIRED_CONFIG = True
    _FIRST_INDEX = 0
    _LAST_INDEX = 35
    __slots__ = '_easiest_difficulty', '_hardest_difficulty'

    def __init__(
        self,
        easiest_difficulty: float = 0.,
        hardest_difficulty: float = 10.,
        *,
        cwd: None | Path = None
    ):
        super().__init__(cwd=cwd)
        self._easiest_difficulty = float(easiest_difficulty)
        self._hardest_difficulty = float(hardest_difficulty)
        assert easiest_difficulty <= hardest_difficulty

    @staticmethod
    def _parse_difficulty(val: str) -> DifficultyFixed | DifficultyRange:
        try:
            return float(val)
        except:
            return tuple([float(x.strip()) for x in val.split('-')])

    @staticmethod
    def _parse_id(val: str) -> str:
        return val.split('/')[-1]

    def _get_random_list(self) -> List[KattisProblem]:
        ret = []
        page = self._request_get(
            f'https://{self.get_url("hostname")}/problems?page={random.randint(self._FIRST_INDEX - 1, self._LAST_INDEX)}&order=%2Bdifficulty_category'
        )
        soup = BeautifulSoup(page.content, 'html.parser')
        table = soup.find_all('table', class_='table2')[0].find_next('tbody')
        for row in table.find_all('tr'):
            ret.append(
                KattisProblem(
                    id=self._parse_id(row.find_next('a', href=True)['href']),
                    difficulty=self._parse_difficulty(
                        row.find_next('span', class_='difficulty_number').text
                    )
                )
            )
        return ret

    def _match(self, problem: KattisProblem) -> bool:
        if isinstance(problem.difficulty, DifficultyFixed):
            return self._easiest_difficulty <= problem.difficulty <= self._hardest_difficulty
        return self._easiest_difficulty <= problem.difficulty[0] \
            and problem.difficulty[1] <= self._hardest_difficulty

    def _problem_already_being_attempted(self, problem: KattisProblem) -> bool:
        if (self.cwd / problem.id).is_dir():
            return True
        return False

    def _act(self) -> None:
        problem: None | KattisProblem = None
        while problem is None:
            for a_problem in self._get_random_list():
                if not self._match(a_problem):
                    continue
                if self._problem_already_being_attempted(a_problem):
                    continue
                problem = a_problem
                break
        Gen(problem.id, cwd=self.cwd).act()
