#!/bin/bash
# Diagnose: a GPU job runs at near-zero utilisation; the IdleGPUAllocation alert
# condition matches. Fix (real life): set num_workers>0. Here: cancel the job.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
echo "gpu util: $(onnode g1 nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader)"
echo "alert series matching: $(docker compose exec -T prometheus promtool query instant http://localhost:9090 'gpu_utilization_percent < 10 and on() slurm_gpu_jobs_running > 0' 2>/dev/null | grep -c '=>')"
hd scancel -u alice >/dev/null 2>&1 || true
