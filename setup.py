from setuptools import setup, find_packages
from kttool.version import version
import pathlib
from distutils.command.install import INSTALL_SCHEMES

HERE = pathlib.Path(__file__).parent
README = (HERE / "README.md").read_text()

for scheme in INSTALL_SCHEMES.values():
    scheme['data'] = scheme['purelib']

required_files = ['kttool/VERSION', 'LICENSE', 'requirements.txt']
for p in (pathlib.Path('kttool') / 'default_templates').iterdir():
    required_files += [str(p.relative_to(pathlib.Path(__file__).parent))]

with open('requirements.txt') as f:
    deps = f.read().splitlines()

setup(
    name='kttool',
    version=version,
    description="Kattis command line tool",
    long_description=README,
    long_description_content_type="text/markdown",
    url="https://github.com/heiseish/kt",
    author="Dao Truong Giang",
    author_email="dtrnggiang@gmail.com",
    license="MIT",
    classifiers=[
        'Operating System :: MacOS :: MacOS X',
        'Operating System :: Microsoft :: Windows',
        'Operating System :: POSIX',
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
    ],
    packages=find_packages(),
    include_package_data=True,
    package_data={'kttool': required_files},
    data_files=[('kttool', required_files)],
    install_requires=deps,
    scripts=['kt']
)
