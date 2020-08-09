from src.ktlib import *
import unittest
import unittest.mock as mock
import os
import shutil


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

    def test_base_action (self):
        action = Action()
        action.read_config_from_file()
        res = action.get_url('kattis', 'hostname')
        self.assertEqual(res, 'https://open.kattis.com/hostname')
    
    def test_write_sample (self):
        data_in = (1, '104', 'biggest', True)
        data_out = (1, '1 24 52', 'biggest', False)
        os.makedirs('biggest', exist_ok=True)

        write_samples(data_in)
        self.assertTrue(os.path.exists('./biggest/in1.txt'))
        with open('./biggest/in1.txt', 'r') as f:
            self.assertEqual(f.read(), '104')

        write_samples(data_out)
        self.assertTrue(os.path.exists('./biggest/ans1.txt'))
        with open('./biggest/ans1.txt', 'r') as f:
            self.assertEqual(f.read(), '1 24 52')
        shutil.rmtree('biggest')

    def test_gen_action (self):
        action = Gen('oddmanout')
        action.act()
        self.assertTrue(os.path.exists('./oddmanout/ans1.txt'))
        self.assertTrue(os.path.exists('./oddmanout/in1.txt'))
        with open('./oddmanout/in1.txt', 'r') as f:
            self.assertEqual(f.read(), """3\n3\n1 2147483647 2147483647\n5\n3 4 7 4 3\n5\n2 10 2 10 5\n""")
        with open('./oddmanout/ans1.txt', 'r') as f:
            self.assertEqual(f.read(), """Case #1: 1\nCase #2: 7\nCase #3: 5\n""")
        shutil.rmtree('oddmanout')

    def test_compare_entity(self):
        lhs = 'Marrie'
        rhs = 'Maria'
        res, diff = compare_entity(lhs, rhs, diff)
        self.assertEqual(res, False)
        self.assertEqual(diff, '\x1b[6;91mMarrie\x1b[0m\x1b[6;92mMaria\x1b[0m')

        lhs = 'Tesla'
        rhs = 'Tesla'
        res, diff = compare_entity(lhs, rhs, diff)
        self.assertEqual(res, True)
        self.assertEqual(diff, 'Tesla ')


