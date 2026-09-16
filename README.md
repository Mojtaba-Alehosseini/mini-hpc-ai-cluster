# mini-hpc-ai-cluster

A small Slurm cluster on one laptop, built by one command and operated the way a
shared system is operated: a scheduler with accounting, fair share and limits;
shared storage with measured IO; containers; one GPU node; monitoring with
alerts; more than one user; and a runbook of failures caused on purpose and then
diagnosed. Every number in this file comes from a command in this repository.

Work in progress. So far: the scheduler, the accounting database, an NFS server,
two CPU nodes and a GPU node are up and configured by Ansible; `/shared` is one
real NFS export mounted on every node; GPU jobs run and Apptainer runs
containers; the IO benchmarks are in place; and Prometheus and Grafana monitor
the cluster with three dashboards and five alert rules. The runbook follows.

Monitoring: `http://localhost:9090` (Prometheus) and `http://localhost:3000`
(Grafana, admin / admin-throwaway) once `make up` is done.

```
make up          # build, start the containers, configure with Ansible, wait for idle nodes
make check       # acceptance tests in tests/run.sh
make idempotent  # a second Ansible run in check mode; must report no change
make down        # stop, keep volumes
make reset       # stop and delete everything
```

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
compose.yaml          the cluster: nfs, db, head, c1, c2, g1 (monitoring comes later)
docker/node/          one image for every node; entrypoint and supervisord configs
ansible/              inventory, site.yml and roles that configure the nodes
slurm/                slurm.conf, cgroup.conf, gres.conf, slurmdbd.conf (source of truth)
storage/              the NFS exports file
containers/           Apptainer image definitions and GPU job scripts
monitoring/           Prometheus config + alerts, the exporters, Grafana dashboards
bench/                IO and small-file benchmarks; results/ holds the CSVs
scripts/              wait_ready.sh; host/ has the WSL2 install and platform checks
tests/run.sh          numbered acceptance tests
docs/                 SETUP.md, DECISIONS.md
```

Benchmarks: `make bench` writes CSVs under `bench/results/`. See `bench/README.md`.

Licence: MIT.
