#!/bin/bash
# GPU smoke test on the gpu partition. It shows two things that are both true on
# this cluster:
#   1. the GPU is real and reachable from a job on the node (nvidia-smi)
#   2. a container runs on the GPU node under Apptainer
# It does NOT claim the GPU works *inside* the container: on WSL2 the GPU is
# /dev/dxg, not /dev/nvidia0, and it does not bridge into the container the way
# a bare-metal driver would (NVML fails with "N/A"). On a real Linux host,
# `apptainer exec --nv` would pass the GPU straight in. See docs/DECISIONS.md.
# Submit: sbatch < containers/jobs/gpu_smoke.sbatch
#SBATCH --job-name=gpu_smoke
#SBATCH --partition=gpu
#SBATCH --gres=gpu:1
#SBATCH --time=00:05:00
#SBATCH --output=/shared/home/%u/gpu_smoke.%j.out
set -euo pipefail

IMG=/shared/images/cuda.sif
echo "node: $(hostname)   gres: ${SLURM_JOB_GRES:-none}"

echo "== GPU on the node (real) =="
srun nvidia-smi -L
srun nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader

echo "== Apptainer container runs on the GPU node =="
srun apptainer exec "$IMG" cat /etc/os-release | head -1
