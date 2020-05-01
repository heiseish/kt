#!/usr/bin/python
import sys
from ktlib import arg_parse, color_red

if __name__ == '__main__':
    try:
        action = arg_parse(sys.argv[1:])
        action.act()
    except Exception as e:
        print(color_red(str(e)))
