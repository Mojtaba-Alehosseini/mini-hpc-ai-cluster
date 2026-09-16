#!/usr/bin/env bash
# Run an external HPC benchmark suite on this cluster, through Slurm.
#
# It expects a checkout of "hpc-patterns" — six computational kernels (heat,
# ising, kmeans, lj, cg, fft), each written as serial C, OpenMP, MPI and CUDA
# with a shared CSV harness and a correctness check. This script stages the
# suite onto the shared NFS export, builds the CPU variants in a node container
# (gcc + mpicc; the node image carries no nvcc, so CUDA variants are skipped),
# and runs a spread of kernels across the serial, OpenMP and MPI paradigms with
# srun — the MPI jobs on four ranks across both compute nodes.
#
# Usage: scripts/run_hpc_patterns.sh [path-to-hpc-patterns]   (default: $HOME/hpc-patterns)
set -euo pipefail

HP_SRC=${1:-${HP_SRC:-$HOME/hpc-patterns}}
COMPOSE=${COMPOSE:-docker compose}

if [ ! -d "$HP_SRC" ]; then
  echo "hpc-patterns checkout not found at: $HP_SRC" >&2
  echo "Pass its path, e.g. scripts/run_hpc_patterns.sh /path/to/hpc-patterns" >&2
  exit 1
fi

base=$(basename "$HP_SRC")
dest="/shared/$base"
csv="$dest/cluster_run.csv"

echo "Staging $HP_SRC -> $dest (shared NFS export) ..."
$COMPOSE exec -T c1 bash -lc "rm -rf '$dest' && mkdir -p '$dest'"
tar cz -C "$(dirname "$HP_SRC")" --exclude="$base/.git" --exclude="$base/bench" "$base" \
  | $COMPOSE exec -T c1 tar xz -C /shared

echo "Building serial + OpenMP + MPI (gcc, mpicc) ..."
$COMPOSE exec -T c1 bash -lc "cd '$dest' && make -s all"

echo "Running kernels through Slurm ..."
$COMPOSE exec -T head bash -lc "
  set -e
  cd '$dest'
  echo 'algo,variant,n,steps,workers,trial,time_s,rate,rate_unit,check_ok,notes' > '$csv'
  srun -p cpu -n1 heat/heat_serial 800 80 2                                  | tail -n +2 >> '$csv'
  OMP_NUM_THREADS=2 srun -p cpu -n1 -c2 heat/heat_omp 800 80 2               | tail -n +2 >> '$csv'
  OMP_NUM_THREADS=2 srun -p cpu -n1 -c2 kmeans/kmeans_omp 400000 20 2        | tail -n +2 >> '$csv'
  OMP_NUM_THREADS=2 srun -p cpu -n1 -c2 lj/lj_omp                            | tail -n +2 >> '$csv'
  srun -p cpu -N2 --ntasks-per-node=2 --mpi=pmix heat/heat_mpi 800 80 2      | tail -n +2 >> '$csv'
  srun -p cpu -N2 --ntasks-per-node=2 --mpi=pmix ising/ising_mpi            | tail -n +2 >> '$csv'
  srun -p cpu -N2 --ntasks-per-node=2 --mpi=pmix cg/cg_mpi 96 1e-6 300 2     | tail -n +2 >> '$csv'
  OMP_NUM_THREADS=2 srun -p cpu -n1 -c2 fft/fft_omp 4096 5 2                 | tail -n +2 >> '$csv'
  srun -p cpu -N2 --ntasks-per-node=2 --mpi=pmix fft/fft_mpi 4096 5 2        | tail -n +2 >> '$csv'
"

echo "Done. Results (also at $csv inside the cluster):"
$COMPOSE exec -T head cat "$csv"
