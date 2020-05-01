from distutils.core import setup
from distutils.extension import Extension
from Cython.Build import cythonize
from Cython.Distutils import build_ext
from Cython.Compiler import Options
from distutils.command.sdist import sdist as _sdist

Options.embed = 'main'
cmdclass = {}
cmdclass.update({'build_ext': build_ext})

extensions = [
    Extension(
        "ktlib",
        sources=["ktlib.pyx"],
        extra_compile_args=["-O3"],
        language="c++"
    ),
]

class sdist(_sdist):
    def run(self):
        # Make sure the compiled Cython files in the distribution are up-to-date
        cythonize(extensions)
        _sdist.run(self)

cmdclass['sdist'] = sdist

setup(
    name='ktlib',
    cmdclass=cmdclass,
    ext_modules=extensions,
)

