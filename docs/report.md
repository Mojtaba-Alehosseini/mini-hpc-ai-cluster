# Report: mini-hpc-ai-cluster

What was built, and what it measures. Every table here is generated from the CSVs
under `bench/results/` by `scripts/gen_report.py`; the numbers are a real run on
the development laptop (Quadro P2000, Docker on WSL2) and will differ on other
hardware.

## What is real and what is emulated

The cluster runs Slurm 23.11 with a real accounting database, cgroup v2 limits, a
kernel NFS server, one Pascal GPU scheduled as a generic resource, and Apptainer
for job containers. It runs as containers on one laptop, so the "nodes" share a
kernel, the network between them is a Docker bridge, and node sizes are Docker
limits. The GPU reaches a job on the node but not inside an Apptainer container,
because WSL2 exposes it as `/dev/dxg`. These seams are listed in the README and
`docs/DECISIONS.md`.

## Storage: sequential and random IO

fio from a compute node, `/shared` (NFS) against `/local` (a node-local ext4
volume), direct IO, medians of the trials.

| Test | /shared (NFS) | /local (disk) | ratio |
|---|---|---|---|
| seq write, 1 job, MB/s | 72.5 | 313 | 4.3x |
| seq write, 4 jobs, MB/s | 122.1 | 313.1 | 2.6x |
| seq read, 1 job, MB/s | 1558.2 | 411 | 0.3x |
| seq read, 4 jobs, MB/s | 2150.7 | 529.6 | 0.2x |
| random 4 KiB read, IOPS | 15079.1 | 39615.9 | 2.6x |

The network file system is several times slower to write than a local disk, as
expected of one server behind a bridge. The read rows are inflated by NFS
server-side caching (a file read right after it is written is served from cache);
`bench/README.md` says so rather than hiding it.

## Storage: many small files versus shards

The experiment that matters for AI datasets on shared storage. The same bytes are
stored as many 4 KiB files and as a few tar shards, then read back.

| Metric | /shared (NFS) | /local (disk) |
|---|---|---|
| create, files/s | 53.5 | 670.5 |
| stat, files/s | 7286 | 113960 |
| read as loose files, MB/s | 3.7 | 20.6 |
| read as tar shards, MB/s | 45.8 | 111.2 |

The headline is the ratio: on the shared file system, reading the data as shards
is about **12.4x** faster than reading it as loose files, and creating
the loose files is roughly ten times slower on NFS than on a local disk because
every file is a metadata round trip to the server. This is why data loaders use
`webdataset`, tar shards or record files.

## Scheduler behaviour

Shown by the acceptance tests and the runbook, with real output in
`runbook/RUNBOOK.md`:

- **Limits.** A job that exceeds its `--mem` is killed `OUT_OF_MEMORY` by the
  cgroup; a job past its `--time` is killed `TIMEOUT`; a fifth job on QoS
  `normal` pends with `QOSMaxJobsPerUserLimit`.
- **Fair share.** After one account (`lab-a`) builds usage, the other account's
  jobs outrank its pending ones: top pending priority 7500 for the heavy user
  versus 15000 for the under-served one.
- **Drain and resume.** A drained node takes no new jobs; new work lands on the
  other node; `scontrol ... state=resume` restores it.

## GPU

The Quadro P2000 (4 GB, Pascal) is scheduled as `gres/gpu` and reachable from a
job on g1 (`nvidia-smi -L` shows it). A short training run:

| Run | device | samples/s | max GPU mem (MiB) |
|---|---|---|---|
| cnn_train 300 steps batch 64 | Quadro P2000 (cuda) | 2289.2 | 161 |

## Monitoring

Prometheus scrapes node, Slurm and GPU exporters; Grafana shows the Cluster, GPU
node and Storage dashboards; five alert rules fire on real conditions and each
has a promtool unit test. The `IdleGPUAllocation` alert catches the most common
GPU waste: a job holding the GPU at under 10% utilisation.

## Limitations

One physical host, so there is no real interconnect and the "nodes" share a
kernel and clock. One Pascal GPU with 4 GB, so no GPU-partition scheduling. NFS
is a single kernel server on a Docker volume, not a parallel file system; there
is no Lustre, GPFS or VAST, which would change the small-file numbers most of
all. The GPU does not enter an Apptainer container on WSL. Every one of these is
stated where it matters rather than smoothed over.
