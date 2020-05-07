from libcpp.string cimport string
from libcpp.vector cimport vector
from libcpp cimport bool as bool_t

cimport ktlib
import unittest
import unittest.mock as mock
import os
import shutil


class CyTester(unittest.TestCase): 
    def test_color(self):
        self.assertEqual(ktlib.color_cyan(b'hi'), b'\x1b[6;96mhi\x1b[0m')
        self.assertEqual(ktlib.color_green(b'universe'), b'\x1b[6;92muniverse\x1b[0m')
        self.assertEqual(ktlib.color_red(b'cosmo'), b'\x1b[6;91mcosmo\x1b[0m')

    def test_make_list_equal(self):
        cdef:
            vector[string] lhs = [b'first', b'second', b'third']
            vector[string] rhs = [b'fourth']
        ktlib.make_list_equal(lhs, rhs)
        self.assertEqual(lhs.size(), rhs.size())
        self.assertEqual(b'fourth', rhs.front())
        self.assertEqual(b'', rhs.back())

        rhs.push_back(b'fifth')
        ktlib.make_list_equal(lhs, rhs, b'sixth')
        self.assertEqual(lhs.size(), rhs.size())
        self.assertEqual(b'sixth', lhs.back())

    def test_base_action (self):
        cdef:
            ktlib.Action action = ktlib.Action()
            string res

        action.read_config_from_file()
        res = action.get_url(b'kattis', b'hostname')
        self.assertEqual(res, b'https://open.kattis.com/hostname')
    
    def test_write_sample (self):
        cdef:
            tuple data_in = (1, '104', 'biggest', True)
            tuple data_out = (1, '1 24 52', 'biggest', False)
        os.makedirs('biggest', exist_ok=True)

        ktlib.write_samples(data_in)
        self.assertTrue(os.path.exists('./biggest/in1.txt'))
        with open('./biggest/in1.txt', 'r') as f:
            self.assertEqual(f.read(), '104')

        ktlib.write_samples(data_out)
        self.assertTrue(os.path.exists('./biggest/ans1.txt'))
        with open('./biggest/ans1.txt', 'r') as f:
            self.assertEqual(f.read(), '1 24 52')
        shutil.rmtree('biggest')

    def test_gen_action (self):
        cdef:
            ktlib.Gen action = ktlib.Gen('oddmanout')
        action.act()
        self.assertTrue(os.path.exists('./oddmanout/ans1.txt'))
        self.assertTrue(os.path.exists('./oddmanout/in1.txt'))
        with open('./oddmanout/in1.txt', 'r') as f:
            self.assertEqual(f.read(), """3\n3\n1 2147483647 2147483647\n5\n3 4 7 4 3\n5\n2 10 2 10 5\n""")
        with open('./oddmanout/ans1.txt', 'r') as f:
            self.assertEqual(f.read(), """Case #1: 1\nCase #2: 7\nCase #3: 5\n""")
        shutil.rmtree('oddmanout')

    def test_compare_entity(self):
        cdef:
            string lhs = b'Marrie'
            string rhs = b'Maria'
            string diff = b''
            bool_t res
        res = ktlib.compare_entity(lhs, rhs, diff)
        self.assertEqual(res, False)
        self.assertEqual(diff, b'\x1b[6;91mMarrie\x1b[0m\x1b[6;92mMaria\x1b[0m')

        lhs = b'Tesla'
        rhs = b'Tesla'
        diff.clear()
        res = ktlib.compare_entity(lhs, rhs, diff)
        self.assertEqual(res, True)
        self.assertEqual(diff, b'Tesla ')


