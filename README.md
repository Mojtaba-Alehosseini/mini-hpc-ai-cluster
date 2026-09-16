# mini-hpc-ai-cluster

A small Slurm cluster on one laptop, built by one command and operated the way a
shared system is operated: a scheduler with accounting, fair share and limits;
shared storage with measured IO; containers; one GPU node; monitoring with
alerts; more than one user; and a runbook of failures caused on purpose and then
diagnosed. Every number in this file comes from a command in this repository.

Work in progress. So far: the scheduler, the accounting database and two CPU
nodes are up and configured by Ansible, and jobs run. Shared storage, the GPU
node, monitoring, the benchmarks and the runbook follow.

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
| One Pascal GPU (Quadro P2000, 4 GB) | Node sizes are Docker CPU and memory limits |
| Users with separate UIDs and accounts | Shared storage is a Docker volume until the NFS step |

## Layout

```
compose.yaml          the cluster: db, head, c1, c2 (g1, nfs and monitoring come later)
docker/node/          one image for every node; entrypoint and supervisord configs
ansible/              inventory, site.yml and roles that configure the nodes
slurm/                slurm.conf, cgroup.conf, slurmdbd.conf (the source of truth)
scripts/              wait_ready.sh; host/ has the WSL2 install and platform checks
tests/run.sh          numbered acceptance tests
docs/                 SETUP.md, DECISIONS.md
```

Licence: MIT.
