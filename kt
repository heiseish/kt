#!/usr/bin/env python
import sys
import signal
from ktlib import arg_parse, color_red, color_green

def exit_gracefully(signum, frame):
    # restore the original signal handler as otherwise evil things will happen
    # in raw_input when CTRL+C is pressed, and our signal handler is not re-entrant
    signal.signal(signal.SIGINT, original_sigint)
    print(color_green('Great is the art of beginning, but greater is the art of ending.'))
    sys.exit(1)

if __name__ == '__main__':
    # store the original SIGINT handler
    original_sigint = signal.getsignal(signal.SIGINT)
    signal.signal(signal.SIGINT, exit_gracefully)
    try:
        action = arg_parse(sys.argv[1:])
        action.act()
    except Exception as e:
        print(color_red(str(e)))
