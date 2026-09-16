#!/bin/bash
# Point gres.conf at a device that does not exist, then restart slurmd on g1.
# slurmd refuses to start and the GPU node never becomes available.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
onnode g1 bash -c 'sed -i "s#File=/dev/dxg#File=/dev/nvidia0#" /etc/slurm/gres.conf; supervisorctl restart slurmd || true'
echo "gres.conf on g1 now points at /dev/nvidia0 (which does not exist on WSL)."
