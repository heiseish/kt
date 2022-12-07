import subprocess
from ..version import version
from ..base import Action
from ..logger import color_cyan, color_green, log, log_red
import requests
import sys

__all__ = ['Update']


class Update(Action):
    _PYPI_PACKAGE_INFO = 'https://pypi.org/pypi/kttool/json'

    def _act(self) -> None:
        pypi_info = requests.get(self._PYPI_PACKAGE_INFO)
        releases = list(pypi_info.json()['releases'])
        if len(releases) == 0:
            log_red('Hmm seems like there is currently no pypi releases :-?')
            return
        current_latest_version = releases[-1]
        if current_latest_version != version:
            subprocess.check_call(
                [
                    sys.executable, "-m", "pip", "install", "--upgrade",
                    "--no-cache-dir", f"kttool=={current_latest_version}"
                ]
            )
            log(
                f'Installed version {color_green(current_latest_version)} successfully!'
            )
        else:
            log(f'You already have the {color_green("latest")} version!')
