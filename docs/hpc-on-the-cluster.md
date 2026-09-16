# Real workloads on the cluster

This is the cluster doing the job it was built for: running real HPC workloads
through Slurm and being watched while it does. Three things are recorded here —
an external kernel suite run across paradigms, standard IO benchmarks built from
source, and the monitoring dashboards under that load. Every number comes from a
command; the reproduce lines are given for each.

## 1. An external kernel suite, across paradigms

[`hpc-patterns`](https://github.com/Mojtaba-Alehosseini/hpc-patterns) is a
separate suite of six computational kernels (heat, ising, kmeans, lj, cg, fft),
each written as serial C, OpenMP, MPI and CUDA behind one CSV harness with a
built-in correctness check. It was staged onto the shared NFS export, built in a
node container with `gcc` and `mpicc`, and run through Slurm — the MPI jobs on
four ranks across both compute nodes. The node image carries no `nvcc`, so the
CUDA variants are skipped (the same WSL/toolkit seam noted elsewhere); the CPU
variants are the point here, and they exercise the scheduler, the cores and the
interconnect.

Reproduce: `scripts/run_hpc_patterns.sh /path/to/hpc-patterns`
Full data: [`bench/results/hpc_patterns_cluster.csv`](../bench/results/hpc_patterns_cluster.csv)

| Kernel | Paradigm | Workers | Placement | Rate | Correctness |
|---|---|---|---|---|---|
| heat | serial | 1 | 1 node | ~721 Mupd/s | rel_err 1.8e-06 ✓ |
| heat | OpenMP | 2 | 1 node | ~657 Mupd/s | rel_err 1.8e-06 ✓ |
| heat | MPI | 4 | 2 nodes | ~78 Mupd/s | rel_err 1.8e-06 ✓ |
| kmeans | OpenMP | 2 | 1 node | ~4.0 GFLOP/s | centroid err 8.4e-03 ✓ |
| lj | OpenMP | 2 | 1 node | ~0.31 Mpart-step/s | energy drift 8e-05 ✓ |
| ising | MPI | 4 | 2 nodes | ~62 Mspin/s | matches Onsager exact ✓ |
| cg | MPI | 4 | 2 nodes | 1,000,000 unknowns, 1376 iters | ‖b−Ax‖/‖b‖ 9.9e-07 ✓ |
| fft | MPI | 4 | 2 nodes | 4096-point | round trip ✓ |

Every run returned `check_ok=1`. Two things are worth calling out. The MPI jobs
carry a communication split in their notes (`t_comm`, `t_halo`, `t_reduce`): at
these small sizes the heat and ising kernels are dominated by halo exchange over
the Docker bridge, which is exactly the behaviour a real small-message
interconnect would show. And the conjugate-gradient solve took a million-unknown
sparse system to a true residual below 1e-6 in 1376 iterations across four
ranks — a genuine distributed linear solve, not a toy.

## 2. IO and metadata: IOR and mdtest

The repository already benchmarks `/shared` (NFS) against `/local` with `fio`
and a small-file experiment. For a second, independent reading, IOR and mdtest —
the standard HPC IO benchmarks — were built from source (`./bootstrap &&
./configure && make`) in a node container and run on both file systems.

Reproduce: `bench/io/ior_mdtest.sh`
Data: [`bench/results/ior_mdtest.csv`](../bench/results/ior_mdtest.csv)

**Bandwidth (IOR, POSIX, 2 tasks):**

| Metric | /local | /shared (NFS) | ratio |
|---|---|---|---|
| write, O_DIRECT | 268.8 MiB/s | 92.8 MiB/s | 2.9× slower |
| read, buffered | 4891 MiB/s | 9936 MiB/s | (cache-served) |

The write figure uses `O_DIRECT` so it is not absorbed by the page cache, and it
shows the expected NFS penalty — the same story `fio` tells. The read figure is
buffered and therefore served from the page cache on both file systems, so it is
not a disk measurement; it is left in and labelled rather than dropped.

**Metadata (mdtest, 2 tasks, 1200 files):**

| Operation | /local | /shared (NFS) | ratio |
|---|---|---|---|
| create | 31,762 ops/s | 102 ops/s | ~310× slower |
| stat | 441,003 ops/s | 507,171 ops/s | (cached) |
| remove | 183,511 ops/s | 97 ops/s | ~1900× slower |

This is the headline for AI data on shared storage. Metadata operations —
creating and removing many small files — are hundreds to nearly two thousand
times slower on NFS, because each one is a synchronous round trip to the server.
Stat is fast on both because the entries are cached. It is why datasets and
checkpoints belong in a few large shards, not millions of loose files.

## 3. The dashboards, under load

The runs above were captured live on the Grafana dashboards that `make up`
provisions. These are screenshots from that session.

**Cluster** — node states, the job queue (including jobs held by the per-user
QoS cap), and CPU allocation climbing as the MPI jobs land:

![Cluster dashboard](figs/dashboard-cluster.jpg)

**GPU node** — a training job driving the Quadro P2000 to ~95% utilisation, with
its memory, temperature and the ~2,300 samples/s throughput:

![GPU node dashboard](figs/dashboard-gpu.jpg)

**Storage** — free space on the export, and the NFS server's network and disk IO
spiking as IOR, mdtest and the kernels move data:

![Storage dashboard](figs/dashboard-storage.jpg)
