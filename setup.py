from distutils.command.sdist import sdist as _sdist
from setuptools import setup, find_packages, Extension
import pathlib

try:
    from Cython.Build import cythonize
    from Cython.Distutils import build_ext
except ImportError:
    cythonize = False

ext = 'pyx' if cythonize else 'cpp'

HERE = pathlib.Path(__file__).parent
README = (HERE / "README.md").read_text()

extensions = [
    Extension(
        "ktlib",
        sources=[f"ktlib.{ext}"],
        extra_compile_args=["-O3"],
        language="c++"
    ),
]

cmdclass = {}


if cythonize:
    extensions = cythonize(extensions)
    cmdclass.update({'build_ext': build_ext})

setup(
    name='kttool',
    cmdclass=cmdclass,
    ext_modules=extensions,
    version="0.0.1",
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
    install_requires=[
        'requests',
        'bs4',
        'emoji',
        'reprint',
        'psutil'
    ],
    scripts=['kt']
)