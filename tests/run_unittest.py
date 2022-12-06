from argparse import Action
from kttool.actions.test import compare_entity
import unittest
from kttool.logger import color_cyan, color_green, color_red
from kttool.utils import make_list_equal


class Tester(unittest.TestCase):
    def test_color(self):
        self.assertEqual(color_cyan('hi'), '\x1b[6;96mhi\x1b[0m')
        self.assertEqual(color_green('universe'), '\x1b[6;92muniverse\x1b[0m')
        self.assertEqual(color_red('cosmo'), '\x1b[6;91mcosmo\x1b[0m')

    def test_make_list_equal(self):
        lhs = ['first', 'second', 'third']
        rhs = ['fourth']
        make_list_equal(lhs, rhs)
        self.assertEqual(lhs.size(), rhs.size())
        self.assertEqual('fourth', rhs.front())
        self.assertEqual('', rhs.back())

        rhs.push_back('fifth')
        make_list_equal(lhs, rhs, 'sixth')
        self.assertEqual(lhs.size(), rhs.size())
        self.assertEqual('sixth', lhs.back())

    def test_base_action(self):
        action = Action()
        action.read_config_from_file()
        res = action.get_url('kattis', 'hostname')
        self.assertEqual(res, 'https://open.kattis.com/hostname')

    def test_compare_entity(self):
        lhs = 'Marrie'
        rhs = 'Maria'
        res, diff = compare_entity(lhs, rhs)
        self.assertEqual(res, False)
        self.assertEqual(diff, '\x1b[6;91mMarrie\x1b[0m\x1b[6;92mMaria\x1b[0m')

        lhs = 'Tesla'
        rhs = 'Tesla'
        res, diff = compare_entity(lhs, rhs)
        self.assertEqual(res, True)
        self.assertEqual(diff, 'Tesla ')
