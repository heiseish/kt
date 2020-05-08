#!/usr/bin/env python
import sys
import signal
from ktlib import arg_parse, color_red, color_green, exit_gracefully


if __name__ == '__main__':
    # store the original SIGINT handler
    signal.signal(signal.SIGINT, exit_gracefully)
    try:
        action = arg_parse(sys.argv[1:])
        action.act()
    except Exception as e:
        print(color_red(str(e)))
