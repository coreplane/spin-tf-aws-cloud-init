#!/usr/bin/env python

import subprocess, socket, os, urllib, time, json, sys, getopt

# max number of bytes to send in one API call
MSG_SIZE_LIMIT = 16*1024 # 16KB

# approximate number of bytes of overhead per API call
MSG_OVERHEAD_FIXED = 250
# approximate number of bytes of overhead per additional line within one API call
MSG_OVERHEAD_PER_LINE = 80

logdna_ingestion_key = os.environ.get('LOGDNA_INGESTION_KEY')
if not logdna_ingestion_key:
    sys.exit(0) # not configured

level = 'INFO'
appname = 'logdna-send'
sitename = os.environ.get('SITENAME','unknown') # ensured by cloud-init runcmd
merge_lines = False # whether to join together successive lines into one "message", if not separated by blank line

opts, args = getopt.gnu_getopt(sys.argv[1:], '', ['level=', 'app=', 'merge-lines'])

for key, val in opts:
    if key == '--level': level = val
    elif key == '--app': appname = val
    elif key == '--merge-lines': merge_lines = True

ingest_url = 'https://logs.logdna.com/logs/ingest'
query_params = {'hostname': socket.gethostname(),
                'now': str(int(time.time()))}

file_list = args if len(args) > 0 else ['-',]
lines = []
merge_buf = []

for filename in file_list:
    fd = open(filename, 'r') if filename != '-' else sys.stdin
    for line in fd.readlines():
        line = line.strip()

        if merge_lines:
            if len(line) < 1: # break to new message
                line = '\n'.join(merge_buf)
                del merge_buf[:]
            else:
                merge_buf.append(line)
                continue # keep accumulating

        lines.append(line)

# finalize merge buffer
if merge_buf:
    lines.append('\n'.join(merge_buf))
    del merge_buf[:]

if not lines: sys.exit(0) # nothing to send

# check against size limit
msg_size = MSG_OVERHEAD_FIXED
for i, line in enumerate(lines):
    msg_size += len(line) + MSG_OVERHEAD_PER_LINE
    if msg_size >= MSG_SIZE_LIMIT:
        if len(lines) < 2:
            # preserve something from the big line
            lines = [lines[0][0:MSG_SIZE_LIMIT//2] + '...', ]
        else:
            # drop last line
            lines = lines[:i]
        lines.append('*** logdna-send.py MESSAGE SIZE LIMIT EXCEEDED, TRUNCATING! ***')
        break

postdata = {'lines': [{'line': line,
                       'app': appname,
                       'level': level.upper(),
                       'env': sitename,
                       } for line in lines]
            }
command = ['curl', ingest_url + '?' + urllib.urlencode(query_params),
           '-s', '-u', logdna_ingestion_key+':',
           '-H', 'Content-Type: application/json; charset=UTF-8',
           '-d', json.dumps(postdata)]
subprocess.check_call(command, stdout=open(os.devnull, 'w'))
