from pathlib import Path
import tempfile
from kttool.actions.gen import Gen
import unittest
import shutil
import pytest


@pytest.mark.parametrize(
    "test_id", ['oddmanout', 'https://open.kattis.com/problems/oddmanout']
)
def test_gen_action(test_id):
    temp_dir = Path(tempfile.gettempdir()) / 'kttool' / 'gen_test'

    action = Gen(test_id, cwd=temp_dir)
    action.act()
    assert (temp_dir / 'oddmanout/ans1.txt').is_file()
    assert (temp_dir / 'oddmanout/in1.txt').is_file()

    with open(temp_dir / 'oddmanout/in1.txt', 'r') as f:
        assert f.read(
        ) == """3\n3\n1 2147483647 2147483647\n5\n3 4 7 4 3\n5\n2 10 2 10 5\n"""
    with open(temp_dir / 'oddmanout/ans1.txt', 'r') as f:
        assert f.read() == """Case #1: 1\nCase #2: 7\nCase #3: 5\n"""

    shutil.rmtree(temp_dir)
