#!/bin/bash
# A job asks for 256 MB but allocates ~700 MB; the cgroup kills it.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
au alice sbatch --mem=256M --wrap="python3 -c 'a=bytearray(700*1024*1024); import time; time.sleep(20)'"
