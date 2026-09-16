#!/bin/bash
# alice submits five jobs on QoS normal, which caps a user at four.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
for i in 1 2 3 4 5; do au alice sbatch --parsable --qos=normal --wrap='sleep 300' >/dev/null; done
echo "submitted 5 jobs as alice on QoS normal."
