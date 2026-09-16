#!/bin/bash
# Stop slurmdbd. Jobs keep running and scheduling, but sacct and fair share stop.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
onnode head supervisorctl stop slurmdbd
echo "slurmdbd stopped. Restart with verify/08."
