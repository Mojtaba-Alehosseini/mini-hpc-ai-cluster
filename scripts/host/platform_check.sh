#!/bin/bash
# Platform check. Answers the three questions that decide the design:
#   1. does the GPU reach a container,
#   2. is an NFS client available to a container,
#   3. can a privileged container delegate cgroup v2 controllers to a child.
# Output is plain text; the findings are copied into docs/DECISIONS.md.
set -u
img=ubuntu:24.04

echo "== host =="
uname -r
docker --version
stat -fc 'cgroup fs: %T' /sys/fs/cgroup
free -g | sed -n 2p
nproc

echo "== 1. GPU in a container =="
docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu22.04 \
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>&1 | tail -1

echo "== 2. NFS client in a privileged container =="
docker run --rm --privileged $img bash -c 'grep -q nfs /proc/filesystems && echo "nfs in /proc/filesystems: yes" || echo "nfs in /proc/filesystems: no"'

echo "== 3. cgroup v2 delegation in a privileged container =="
docker run --rm --privileged $img bash -c '
echo "controllers: $(cat /sys/fs/cgroup/cgroup.controllers)"
mkdir /sys/fs/cgroup/system && echo $$ > /sys/fs/cgroup/system/cgroup.procs || { echo "move self: failed"; exit 0; }
if echo "+cpuset +cpu +memory +pids" > /sys/fs/cgroup/cgroup.subtree_control; then
    echo "subtree_control: $(cat /sys/fs/cgroup/cgroup.subtree_control)"
    mkdir /sys/fs/cgroup/job && echo 100M > /sys/fs/cgroup/job/memory.max && echo "memory.max on a child: ok"
    echo 0-1 > /sys/fs/cgroup/job/cpuset.cpus && echo "cpuset.cpus on a child: ok"
else
    echo "subtree_control: write failed"
fi'
