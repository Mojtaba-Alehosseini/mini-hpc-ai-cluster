#!/bin/bash
# Diagnose: sprio/squeue show carol's pending jobs outranking bob's; sshare shows
# lab-a's usage is high and lab-b's is low.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
echo "bob top pending priority:   $(hd squeue -h -u bob   -t PENDING -o '%Q' | sort -rn | head -1)"
echo "carol top pending priority: $(hd squeue -h -u carol -t PENDING -o '%Q' | sort -rn | head -1)"
hd sshare -h -o Account,RawShares,RawUsage,FairShare -P | grep -E 'lab-a|lab-b'
hd scancel -u bob >/dev/null 2>&1 || true; hd scancel -u carol >/dev/null 2>&1 || true
