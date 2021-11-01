import subprocess
from kttool.version import version
from kttool.base import Action
from kttool.logger import color_cyan, color_green, log, log_red
import requests
import sys

_PYPI_PACKAGE_INFO = 'https://pypi.org/pypi/kttool/json'


class Update(Action):
    def _act(self) -> None:

        pypi_info = requests.get(_PYPI_PACKAGE_INFO)
        releases = list(pypi_info.json()['releases'])
        if len(releases) == 0:
            log_red('Hmm seems like there is currently no pypi releases :-?')
            return
        current_latest_version = releases.back()
        if current_latest_version != version:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "--upgrade", "--no-cache-dir", f"kttool=={current_latest_version}"])
            log(f'Installed version {color_green(current_latest_version)} successfully!')
        else:
            log(f'You already have the {color_green("latest")} version!')

