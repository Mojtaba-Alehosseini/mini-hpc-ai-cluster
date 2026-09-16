# Setup on a Windows laptop

Manual steps, done once. Everything after this is `make up`.

## 1. WSL2 with Ubuntu 24.04

`wsl --version` must report WSL 2.x. `wsl --install -d Ubuntu-24.04` if there is
no Ubuntu yet. The cluster needs about 20 GB of disk. If drive C: is short, put
the distribution on another drive:

```powershell
wsl --shutdown
wsl --export Ubuntu E:\wsl\Ubuntu-hpc\ext4.vhdx --vhd
wsl --import-in-place Ubuntu-hpc E:\wsl\Ubuntu-hpc\ext4.vhdx
```

Give the WSL2 virtual machine enough memory. In `C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
memory=20GB
swap=4GB
vmIdleTimeout=-1
```

`vmIdleTimeout=-1` matters: by default WSL2 stops the virtual machine about a
minute after the last terminal closes, and the cluster stops with it. The
containers have `restart: unless-stopped`, so they come back when Docker
starts, but the pause would still break a running benchmark.

Inside the distribution, `/etc/wsl.conf` needs systemd:

```ini
[boot]
systemd = true
```

`wsl --shutdown` after both changes.

## 2. NVIDIA driver

A current Windows NVIDIA driver is enough; WSL2 uses it directly. Check with
`nvidia-smi` inside Ubuntu. Tested with driver 582.16 on a Quadro P2000.

## 3. Docker Engine and the NVIDIA container toolkit

Inside the distribution, as root:

```bash
bash scripts/host/install_docker_wsl.sh <your-user>
```

Log in again so the `docker` group applies, then:

```bash
bash scripts/host/platform_check.sh
```

The three answers (GPU, NFS, cgroup) are recorded in `docs/DECISIONS.md`.

## 4. Clone and start

Clone inside the WSL2 file system, not under `/mnt/c`: Windows drives are slow
from WSL2 and the storage numbers would measure the wrong thing.

```bash
git clone https://github.com/Mojtaba-Alehosseini/mini-hpc-ai-cluster.git
cd mini-hpc-ai-cluster
make up
make check
```
