import os
import pty
import sys

os.environ['COLUMNS'] = '5000'
os.environ['TERM'] = 'dumb'
os.environ['NO_COLOR'] = '1'
sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))
