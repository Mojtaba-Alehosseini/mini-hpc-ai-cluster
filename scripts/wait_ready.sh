#!/bin/bash
# Wait until slurmctld answers and every configured node is idle.
# Exit 1 after the timeout so "make up" fails loudly instead of silently.
set -u
timeout=${1:-300}
start=$(date +%s)
compose="docker compose"

while true; do
    if $compose exec -T head scontrol ping 2>/dev/null | grep -q UP; then
        # Every node must report idle, none down, drained or unknown.
        states=$($compose exec -T head sinfo -h -N -o '%t' 2>/dev/null | sort -u | tr '\n' ' ')
        if [ -n "$states" ] && [ "$states" = "idle " ]; then
            echo "cluster ready after $(( $(date +%s) - start )) s"
            exit 0
        fi
    fi
    if [ $(( $(date +%s) - start )) -ge "$timeout" ]; then
        echo "cluster not ready after ${timeout} s; node states: ${states:-none}" >&2
        $compose exec -T head sinfo -N 2>/dev/null >&2 || true
        exit 1
    fi
    sleep 3
done
