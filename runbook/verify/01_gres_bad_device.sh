#!/bin/bash
# Diagnose: g1 is down/unavailable; slurmd log shows it cannot stat the device.
# Fix: restore gres.conf to /dev/dxg and restart slurmd.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
echo "state of g1:"; hd sinfo -h -n g1 -o '%t %E'
echo "slurmd log:"; onnode g1 bash -c 'grep -i gres /var/log/slurm/slurmd.log | tail -2'
onnode g1 bash -c 'sed -i "s#File=/dev/nvidia0#File=/dev/dxg#" /etc/slurm/gres.conf; supervisorctl restart slurmd'
sleep 3; hd scontrol update nodename=g1 state=resume 2>/dev/null || true; sleep 2
echo "after fix: g1 $(hd sinfo -h -n g1 -o '%t')"
