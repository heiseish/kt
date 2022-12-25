#!/usr/bin/env python
import sys
import signal
from kttool.parser import arg_parse
from kttool.logger import log_red, log
from kttool.utils import exit_gracefully
import traceback

if __name__ == '__main__':
    # store the original SIGINT handler
    signal.signal(signal.SIGINT, exit_gracefully)
    try:
        action = arg_parse(sys.argv[1:])
        if action is not None:
            action.act()
    except Exception as e:
        log_red(str(e))
        log(traceback.format_exc())
