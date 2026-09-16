#!/bin/bash
# Diagnose: sacct shows the job TIMEOUT.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
j=$(hd sacct -n -u alice -X -o JobID -P | tail -1 | tr -d ' ')
echo "job $j: $(hd sacct -j "$j" -X -n -o State -P | tr -d ' ')"
