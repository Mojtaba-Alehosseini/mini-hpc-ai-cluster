# Decisions

Every choice made without a second opinion, with the date and the reason.
Newest at the bottom.

## 2026-09-16

**D1. Host: Docker Engine inside a WSL2 Ubuntu 24.04 distribution, not Docker Desktop.**
Docker was not installed. Docker Desktop needs an administrator install on
Windows; Docker Engine inside WSL2 does not, and it runs on a host with systemd,
cgroup v2 and loadable NFS kernel modules, which is closer to a Linux server.
The distribution is a copy of the existing Ubuntu, named `Ubuntu-hpc`, placed on
drive E: because drive C: had 24 GB free and the images, datasets and benchmark
files need about 20 GB. Steps in `docs/SETUP.md`.

**D2. Node image: Ubuntu 24.04 with Slurm 23.11 from the distribution packages.**
Ubuntu 24.04 packages Slurm 23.11.4, so no source build. Rocky Linux 9 with EPEL
would have given 22.05. One image serves head, compute and GPU nodes: the NVIDIA
container toolkit injects the driver libraries into the GPU node at run time, and
the PyTorch Apptainer image carries its own CUDA runtime.

**D3. Daemons under supervisord, in the foreground, no systemd in the containers.**
`munged -F`, `slurmctld -D`, `slurmdbd -D`, `slurmd -D`. systemd inside
containers needs extra privileges and hides failures behind unit restarts;
supervisord keeps the logs in plain files that the runbook can quote.

**D4. Shared storage starts as a Docker volume mounted at /shared on every node.**
The NFS server (kernel `nfsd` in a privileged container, or NFS-Ganesha) is
tested when the storage layer is built. The `nfs` and `nfsd` modules load on the
WSL2 kernel 6.6.87.2, so the client side is expected to work. Until then the
cluster has a shared file system with the same paths (`/shared/home`,
`/shared/data`, `/shared/ckpt`), so nothing downstream waits for it.

**D5. Accounting is bootstrapped by `accounting.sh`, run by `make up`.**
Accounts, users, fair shares and QoS are created with `sacctmgr -i`, idempotent.
The Ansible `slurm_head` role runs the script, so the definitions live in one
place.

**D6. The GPU is a Quadro P2000 with 4 GB, not 5 GB.**
`nvidia-smi` reports 4096 MiB. Every document says 4 GB.

**D7. Superseded by D9: configuration was first mounted read-only and copied at boot.**
The containers first copied `slurm.conf`, `cgroup.conf` and `slurmdbd.conf` from
a read-only bind mount at start. This was replaced by Ansible-managed
configuration (D9); the files under `slurm/` stay the single source of truth.

**D8. Node sizes.** c1 and c2: 2 CPUs (pinned with `cpuset`) and 2 GB each,
enforced by Docker. `slurm.conf` says `CPUs=2 RealMemory=1800` with
`SlurmdParameters=config_overrides`, because a container reports the host's
12 CPUs and 20 GB and Slurm would otherwise schedule against those.

## 2026-09-17

**D9. Ansible owns the configuration; the containers carry no config.**
The bind mounts for `slurm/` and the munge key were removed. The containers
start with packages and the init script only. `ansible/site.yml`, run over the
`community.docker.docker` connection, installs the munge key, the Slurm
configuration, the users, the accounts and the QoS, and starts the daemons.
`slurm/*.conf` and `secrets/munge.key` are the single source of truth; Ansible
copies them in. `make idempotent` (a `--check` run) proves a second run changes
nothing.

**D10. Daemons start with `autostart=false`; Ansible starts them.**
The munge key and the configuration are not in the image, so a daemon started at
container boot would fail. supervisord therefore starts nothing on its own;
Ansible starts munged, then slurmdbd and slurmctld on the head, then slurmd on
the compute nodes, in that order, once each has what it needs. `autorestart` is
on, so a daemon that crashes during operation comes back. The one cost: after a
host reboot the containers restart but the daemons stay down until `make up` is
run again. `make up` is idempotent and takes under a minute, so this is a
deliberate trade for a clean, ordered bring-up over a fragile boot-time race.

**D11. cgroup delegation stays in the entrypoint, not Ansible.**
Moving the container's init process into `init.scope` and enabling the cgroup v2
controllers must happen in PID 1 at start, before any step runs. That is a
container-runtime concern, so it lives in `entrypoint.sh`. Ansible owns cluster
configuration, not the container's own cgroup bootstrap.

## 2026-09-18

**D12. Shared storage is a real kernel NFS server, exporting a Docker volume.**
`/shared` is now one NFS export, not a per-node volume, so it is genuinely one
file system: a file written on the head has the same inode on c1 and c2 (test
05). The server is a container running the Linux kernel NFS server (`rpc.nfsd`,
`rpc.mountd`), NFSv4 only. The one constraint that shaped the design: the kernel
NFS server cannot export a container's overlay filesystem ("does not support NFS
export"), so the export directory is a Docker named volume (`shared` at
`/exports`), which is backed by real ext4. The `nfs_server` role loads the
export and starts the daemons; the `nfs_client` role mounts `nfs:/` at `/shared`
on every node. NFS-Ganesha (userspace) was the fallback if the kernel server had
not worked; it did, and the kernel server is the one real sites run.

**D13. The head and nfs nodes run privileged, like the compute nodes.**
Mounting NFS inside a container needs `CAP_SYS_ADMIN`, and the kernel NFS server
needs to load exports, so `head`, `nfs`, `c1` and `c2` are all privileged. On a
single-host test cluster this is acceptable; a real deployment would narrow the
capabilities. Stated in the "real and emulated" table.

**D14. The NFS mount is re-made on every `make up`, not persisted.**
An NFS mount inside a container does not survive a container restart, and there
is no fstab boot mount. The `nfs_client` role mounts `/shared` when it is not
already mounted, so `make up` restores it and a second run is a no-op. Same
trade as D10: a clean, ordered bring-up over a boot-time mount.
