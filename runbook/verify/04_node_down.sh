#!/bin/bash
# Diagnose with sinfo -R; fix by restarting slurmd and resuming the node.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
hd sinfo -R | grep c2 || true
onnode c2 supervisorctl start slurmd; sleep 3
hd scontrol update nodename=c2 state=resume; sleep 2
echo "after fix: c2 $(hd sinfo -h -n c2 -o '%t')"
