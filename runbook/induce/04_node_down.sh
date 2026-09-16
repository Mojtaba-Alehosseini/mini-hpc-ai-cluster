#!/bin/bash
# Stop slurmd on c2. slurmctld marks the node DOWN after SlurmdTimeout; an
# operator marks it down at once here so the effect is immediate.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
onnode c2 supervisorctl stop slurmd
hd scontrol update nodename=c2 state=down reason="slurmd not responding"
echo "c2 slurmd stopped and node marked down."
