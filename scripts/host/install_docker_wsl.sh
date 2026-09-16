#!/bin/bash
# Host setup for a WSL2 Ubuntu 24.04 distribution. Run once as root.
# Installs Docker Engine, the compose plugin and the NVIDIA container toolkit,
# and loads the NFS kernel modules at boot. See docs/SETUP.md.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
user=${SUDO_USER:-${1:-}}

apt-get update -q
# ansible ships with the community.docker collection, which provides the docker
# connection plugin the playbook uses to reach the containers.
apt-get install -y -q ca-certificates curl gnupg make git python3-venv nfs-common ansible
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" \
    > /etc/apt/sources.list.d/docker.list
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -sL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -q
apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    nvidia-container-toolkit
[ -n "$user" ] && usermod -aG docker "$user"
nvidia-ctk runtime configure --runtime=docker
systemctl enable --now docker
systemctl restart docker

# NFS client and server modules for the shared storage tests.
printf 'nfs\nnfsd\n' > /etc/modules-load.d/nfs.conf
modprobe nfs && modprobe nfsd

docker --version
docker compose version
nvidia-ctk --version | head -1
echo "host setup done"
