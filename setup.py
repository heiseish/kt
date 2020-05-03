from Cython.Build import cythonize
from Cython.Distutils import build_ext
from distutils.command.sdist import sdist as _sdist
from setuptools import setup, find_packages, Extension
import pathlib

HERE = pathlib.Path(__file__).parent
README = (HERE / "README.md").read_text()
deps = []
with open('requirements.txt', 'r') as f:
    deps = f.readlines()

extensions = [
    Extension(
        "ktlib",
        sources=["ktlib.pyx"],
        extra_compile_args=["-O3"],
        language="c++"
    ),
]
cmdclass = {}
cmdclass.update({'build_ext': build_ext})
class sdist(_sdist):
    def run(self):
        # Make sure the compiled Cython files in the distribution are up-to-date
        cythonize(extensions)
        _sdist.run(self)
cmdclass['sdist'] = sdist

setup(
    name='kttool',
    cmdclass=cmdclass,
    ext_modules=extensions,
    version="1.0.2",
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
    install_requires=deps,
    scripts=['kt']
)

