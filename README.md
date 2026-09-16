# mini-hpc-ai-cluster

A small Slurm cluster on one laptop, built by one command and operated the way a
shared system is operated: a scheduler with accounting, fair share and limits;
shared storage with measured IO; containers; one GPU node; monitoring with
alerts; more than one user; and a runbook of failures caused on purpose and then
diagnosed. Every number in this file comes from a command in this repository.

A scheduler with accounting, fair share and limits; one real NFS export mounted on
every node; Apptainer for job containers; one GPU node; Prometheus and Grafana
with three dashboards and five unit-tested alert rules; and a runbook of ten
failures caused on purpose and diagnosed. Fourteen acceptance tests pass from a
cold `make up`. The full write-up is `docs/report.md`.

Monitoring: `http://localhost:9090` (Prometheus) and `http://localhost:3000`
(Grafana, admin / admin-throwaway) once `make up` is done.

```
make up          # build, start the containers, configure with Ansible, wait for idle nodes
make check       # the 14 acceptance tests in tests/run.sh
make bench       # IO and small-file benchmarks -> bench/results/*.csv
make report      # regenerate docs/report.md from those CSVs
make idempotent  # a second Ansible run in check mode; must report no change
make down        # stop, keep volumes
make reset       # stop and delete everything
```

## Results (a run on the development laptop; see docs/report.md)

- **Shared storage IO.** Sequential write to `/shared` (NFS) ~72 MB/s versus ~313
  MB/s to a node-local disk.
- **Small files, the headline.** On `/shared`, reading a dataset as tar shards is
  about **12x** faster than as loose 4 KiB files (46 vs 3.7 MB/s), and NFS creates
  small files ~10x slower than a local disk (54 vs 670 files/s). Pack datasets
  into shards.
- **Scheduler.** Over-memory jobs are killed `OUT_OF_MEMORY`, over-time jobs
  `TIMEOUT`, the per-user QoS cap holds, and fair share lifts an under-served
  account (pending priority 15000 vs 7500). Real output in `runbook/RUNBOOK.md`.
- **GPU.** A CNN training job scheduled on the GPU node through Slurm `gres/gpu`
  drives the Quadro P2000 to 99% utilisation: ~2290 samples/s on synthetic 64x64
  images, 161 MiB peak GPU memory.

The containers carry only packages. Ansible (`ansible/site.yml`, over the
Docker connection) installs the munge key, the Slurm configuration, the users
and the accounts, and starts the daemons. It is idempotent.

Setup on Windows: `docs/SETUP.md`. Decisions and their reasons: `docs/DECISIONS.md`.

## What is real and what is emulated

| Real | Emulated |
|---|---|
| Slurm 23.11 with slurmdbd accounting, fair share, QoS limits | Nodes are containers on one kernel, not machines |
| cgroup v2 confinement of job steps | The `cluster` network is a Docker bridge, not a switch |
| Kernel NFS server; `/shared` is one export mounted on every node | Node sizes are Docker CPU and memory limits |
| One Pascal GPU (Quadro P2000, 4 GB), scheduled as a Slurm GRES | The nodes run privileged (NFS mount, cgroup, GPU) |
| Apptainer runs job containers on the nodes | GPU is `/dev/dxg` on WSL, so it does not enter an Apptainer container |
| Prometheus + Grafana, 3 dashboards, 5 alert rules unit-tested | Users with separate UIDs and accounts, one physical host |

## Layout

```
compose.yaml          the cluster: nfs, db, head, c1, c2, g1, prometheus, grafana
docker/node/          one image for every node; entrypoint and supervisord configs
ansible/              inventory, site.yml and roles that configure the nodes
slurm/                slurm.conf, cgroup.conf, gres.conf, slurmdbd.conf (source of truth)
storage/              the NFS exports file
containers/           Apptainer image definitions and GPU job scripts
monitoring/           Prometheus config + alerts, the exporters, Grafana dashboards
runbook/              RUNBOOK.md and induce/verify scripts for ten incidents
bench/                IO and small-file benchmarks; results/ holds the CSVs
scripts/              wait_ready.sh, gen_report.py; host/ has WSL2 setup + checks
tests/run.sh          the 14 numbered acceptance tests
docs/                 SETUP.md, DECISIONS.md, report.md (generated)
```

Benchmarks: `make bench` writes CSVs under `bench/results/`, then `make report`
regenerates `docs/report.md` from them. See `bench/README.md`.

Licence: MIT.
