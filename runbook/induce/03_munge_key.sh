#!/bin/bash
# Replace the munge key on c2 so its credentials no longer match the cluster.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
onnode c2 bash -c 'cp /etc/munge/munge.key /tmp/good.key; dd if=/dev/urandom of=/etc/munge/munge.key bs=1024 count=1 status=none; chown munge:munge /etc/munge/munge.key; chmod 400 /etc/munge/munge.key; supervisorctl restart munged'
echo "c2 now has a mismatched munge key. Restore with verify/03 or /tmp/good.key."
