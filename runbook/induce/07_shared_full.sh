#!/bin/bash
# Fill the shared file system so a checkpoint write fails. Uses a bounded tmpfs
# on the nfs node as a safe stand-in (the real /exports is ~1 TB). ENOSPC is the
# same error a full /shared gives.
set -e; cd "$(dirname "$0")/../.."; . runbook/lib.sh
onnode nfs bash -c 'mkdir -p /mnt/fulltest && mount -t tmpfs -o size=16M tmpfs /mnt/fulltest; dd if=/dev/zero of=/mnt/fulltest/ckpt.bin bs=1M count=64 2>&1 | grep -i "no space" || true'
onnode nfs umount /mnt/fulltest 2>/dev/null || true
