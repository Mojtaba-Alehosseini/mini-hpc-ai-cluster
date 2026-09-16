#!/bin/bash
# A job runs past its one-minute time limit and is killed at TIMEOUT.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
au alice sbatch --time=00:01:00 --wrap='sleep 300'
