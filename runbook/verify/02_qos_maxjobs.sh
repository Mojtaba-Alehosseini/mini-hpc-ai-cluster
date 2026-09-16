#!/bin/bash
# Diagnose: the fifth job pends with reason QOSMaxJobsPerUserLimit.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
r=$(hd squeue -h -u alice -t PENDING -o '%r' | head -1)
echo "pending reason: $r"
hd scancel -u alice >/dev/null 2>&1 || true
[ "$r" = "QOSMaxJobsPerUserLimit" ]
