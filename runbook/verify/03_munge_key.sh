#!/bin/bash
# Diagnose: commands from c2 fail to authenticate. Fix: restore the key.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
echo "symptom from c2:"; onnode c2 sinfo 2>&1 | head -1
onnode c2 bash -c 'cp /tmp/good.key /etc/munge/munge.key; chown munge:munge /etc/munge/munge.key; chmod 400 /etc/munge/munge.key; supervisorctl restart munged; sleep 2; supervisorctl restart slurmd'
sleep 3; hd scontrol update nodename=c2 state=resume 2>/dev/null || true; sleep 2
echo "after fix: c2 $(hd sinfo -h -n c2 -o '%t')"
