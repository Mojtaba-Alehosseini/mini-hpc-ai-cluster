#!/bin/bash
# Diagnose: sacct/sshare fail (connection refused to 6819) while jobs still run.
# Fix: restart slurmdbd; the accounting catches up.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
echo "sacct while down:"; hd sacct -j 1 2>&1 | head -1
onnode head supervisorctl start slurmdbd; sleep 5
echo "after restart, sacct works: $(hd sacct -n -X -o JobID -P 2>&1 | tail -1)"
