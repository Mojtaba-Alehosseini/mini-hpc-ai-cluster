#!/bin/bash
# A job holds the GPU but does no work (num_workers=0 in real life; sleep here).
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
au alice sbatch --partition=gpu --gres=gpu:1 --wrap='sleep 900'
echo "GPU job submitted; it holds the GPU while utilisation stays near 0."
