#!/bin/bash
# Short CNN training run on the GPU partition, used as the live load for the
# monitoring dashboards. It runs directly on the node (the GPU does not enter an
# Apptainer container on WSL; see docs/DECISIONS.md), using the shared venv that
# make train_env builds. Submit: sbatch < containers/jobs/cnn_train.sbatch
#SBATCH --job-name=cnn_train
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=00:10:00
#SBATCH --output=/shared/home/%u/cnn_train.%j.out
set -euo pipefail
PY=/shared/venv/bin/python
echo "node: $(hostname)   python: $PY"
# train_demo.py is copied to /shared/jobs by "make train_env"
srun "$PY" /shared/jobs/train_demo.py 300
