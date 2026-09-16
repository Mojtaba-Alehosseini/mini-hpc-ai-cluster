#!/bin/bash
# bob's account floods the queue and builds usage; then carol submits and her
# jobs, from the under-served account, outrank his pending ones.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
for i in $(seq 20); do au bob sbatch --parsable --qos=high --wrap='sleep 300' >/dev/null; done
echo "bob submitted 20; wait ~30s for usage to build, then run induce as carol:"
echo "  for i in \$(seq 5); do docker compose exec -T -u carol -w /shared/home/carol head sbatch --qos=high --wrap='sleep 300'; done"
