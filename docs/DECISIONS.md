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

**D15. The IO benchmark compares `/shared` against a node-local ext4 volume.**
To measure the cost of the network file system honestly, `bench/io/run.sh` runs
fio against `/shared` (NFS) and against `/local`, a Docker volume mounted only on
c1 as a stand-in for a node-local disk. Read results are influenced by NFS
server-side caching, which is stated in `bench/README.md` rather than hidden. The
small-file experiment (`bench/io/smallfiles.sh`) is the one that matters for AI
datasets: it shows the metadata cost of many tiny files on a shared file system
versus a few tar shards.

## 2026-09-19

**D16. One GPU node, g1, with the P2000 as a Slurm generic resource.**
The NVIDIA container runtime passes the host GPU into the g1 container (compose
`reservations.devices`), and `nvidia-smi` inside g1 sees the P2000. On WSL2 the
GPU device is `/dev/dxg`, not `/dev/nvidia0` as on a bare-metal driver, so
`gres.conf` on g1 points `File` at `/dev/dxg` (slurmd refuses to start if the
device file does not exist). `slurm.conf` declares `NodeName=g1 Gres=gpu:p2000:1`
and a `gpu` partition, and `GresTypes=gpu` turns the tracking on. A job asks for
the GPU with `--gres=gpu:1`. The `slurm_compute` role installs `gres.conf` only
on nodes in the `gpu` inventory group, so only g1 gets it. This WSL GPU path is
one of the emulation seams, noted in the README.

**D17. Job containers run under Apptainer, built into the node image.**
Apptainer is installed from its PPA in the image, so the setuid components are
present and a job (running as an ordinary user) can `apptainer exec`. GPU jobs
run `apptainer exec --nv`, which injects the driver at run time; the container
image itself carries no driver. `make images` builds `containers/cuda.def` into
`/shared/images/cuda.sif` once, and `containers/jobs/gpu_smoke.sbatch` runs it on
the gpu partition to prove the GPU reaches a container.

**D18. `ConstrainDevices=no`: the GPU is scheduled, not cgroup-isolated.**
With one GPU and one GPU node, Slurm's GRES scheduling is enough to hand the GPU
to one job at a time. Restricting `/dev/nvidia*` with the cgroup device
controller (`ConstrainDevices=yes`) is fiddly inside a container and buys nothing
here, so it is left off. On a multi-GPU node it would matter; noted as a
limitation.

**D19. The GPU works on the node but not inside an Apptainer container, on WSL.**
`nvidia-smi` and CUDA work in a job on g1 (test 03), because WSL exposes the GPU
through `/dev/dxg` and the driver libraries under `/usr/lib/wsl`. They do not work
inside an `apptainer exec` container: the libraries were bound in and put on
`LD_LIBRARY_PATH`, but NVML still fails with "N/A" because the WSL GPU stack does
not bridge into the container's namespace the way a bare-metal `/dev/nvidia0`
does. This is a property of WSL2, not of the cluster: on a real Linux host,
`apptainer exec --nv` passes the GPU straight in. So `gpu_smoke.sbatch` shows the
GPU on the node and a container running under Apptainer, and does not pretend the
GPU is inside the container. A GPU training job therefore runs directly on g1
(next), not wrapped in Apptainer. Stated in the "real and emulated" table.
