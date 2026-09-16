# Runbook

Ten failures, each caused on purpose on this cluster and then diagnosed as if the
cause were unknown. Every command and every line of output below is real, taken
from this cluster; output is trimmed, not edited. Each incident has a script under
`induce/` that causes it and one under `verify/` that diagnoses and fixes it. The
memory, time-limit, fair-share and drain incidents also run inside `make check`
(tests 06, 07, 10, 11). Incidents 3, 7 and 8 are disruptive and are meant to be
run by hand.

Helpers used below are in `runbook/lib.sh` (`hd` runs a command on the head node,
`onnode c2 ...` runs one in a node container).

---

## 1. GPU node never comes up (gres.conf names a device that does not exist)

**Symptom.** After a change, GPU jobs never start and `sinfo` shows the GPU node
unavailable.

**Diagnosis.**
```
$ onnode g1 tail -f /var/log/slurm/slurmd.log
fatal: can't stat gres.conf file /dev/nvidia0: No such file or directory
error: Waiting for gres.conf file /dev/nvidia0
```
slurmd refuses to start because `gres.conf` points `File=` at a device that does
not exist. On this WSL host the GPU is `/dev/dxg`, not `/dev/nvidia0`.

**Root cause.** `gres.conf` device path does not match the node's real device.

**Fix.** Point `gres.conf` at the real device and restart slurmd:
```
# /etc/slurm/gres.conf on g1
Name=gpu Type=p2000 File=/dev/dxg
$ onnode g1 supervisorctl restart slurmd
$ hd scontrol update nodename=g1 state=resume
```

**Prevention.** Keep `gres.conf` in version control with the correct device for
the platform (documented in `docs/DECISIONS.md`); slurmd failing to start is loud
in its log, so alert on the node being down (`NodeDown`).

---

## 2. Job stuck PENDING with reason `QOSMaxJobsPerUserLimit`

**Symptom.** A user submits several jobs; some run, one sits in the queue.

**Diagnosis.**
```
$ hd squeue -u alice -o '%.6i %.8T %r'
   110  PENDING QOSMaxJobsPerUserLimit
   107  RUNNING None
   108  RUNNING None
   109  RUNNING None
   106  RUNNING None
$ hd scontrol show job 110 | grep -o 'Reason=[^ ]*'
Reason=QOSMaxJobsPerUserLimit
```

**Root cause.** QoS `normal` caps a user at four jobs (`MaxJobsPerUser=4`). The
fifth waits until one finishes. This is a limit working as designed, not a fault.

**Fix.** Nothing to fix: the job runs when a slot frees. If the user needs more,
they use a QoS that allows it, or the admin raises the cap with `sacctmgr`.

**Prevention.** Document the per-user caps so users expect them.

---

## 3. `Invalid credential` after the munge key changes on a node (by hand)

**Symptom.** Every Slurm command from one node fails; the node falls out of the
cluster.

**Diagnosis.**
```
$ onnode c2 sinfo
slurm_load_partitions: Unexpected message received
```
munge signs every Slurm message. When c2's key stopped matching the rest of the
cluster, the controller rejected its messages.

**Root cause.** The munge key on c2 differs from the key on the other nodes.

**Fix.** Copy the correct key back, fix its ownership and mode, restart munge and
slurmd:
```
$ onnode c2 install -o munge -g munge -m 0400 /path/good/munge.key /etc/munge/munge.key
$ onnode c2 supervisorctl restart munged && onnode c2 supervisorctl restart slurmd
$ hd scontrol update nodename=c2 state=resume
```

**Prevention.** Distribute the one key with Ansible (the `munge` role) so every
node has the same key; never edit it by hand.

---

## 4. Node goes `DOWN` after slurmd dies

**Symptom.** Jobs stop landing on a node; `sinfo` shows it down.

**Diagnosis.**
```
$ hd sinfo -R
REASON               USER      TIMESTAMP           NODELIST
slurmd not respondin root      2026-09-16T15:57:42 c2
```
The controller stops hearing from `slurmd` on c2 (after `SlurmdTimeout`) and
marks the node down. New jobs avoid it:
```
$ hd sacct -j 113 -X -n -o NodeList
c1
```

**Root cause.** `slurmd` on the node stopped (crash, OOM, or the container died).

**Fix.** Restart slurmd and resume the node:
```
$ onnode c2 supervisorctl start slurmd
$ hd scontrol update nodename=c2 state=resume
after resume: c2 idle
```

**Prevention.** `autorestart` on slurmd under supervisord; the `NodeDown` alert
fires within two minutes so an operator notices before users do.

---

## 5. Job killed for using more memory than it asked for

**Symptom.** A job dies early; the user says it "just crashed".

**Diagnosis.**
```
$ hd sacct -j <id> -X -o JobID,State,ExitCode
State=OUT_OF_MEMORY   (ExitCode 0:125)
```
The job requested `--mem=256M` but allocated about 700 MB. `task/cgroup` with
`ConstrainRAMSpace=yes` caps the step at what it asked for and the kernel kills it.

**Root cause.** The job under-requested memory.

**Fix.** Re-submit with an honest `--mem`. The cluster will not let a job exceed
its request, which is the point: one job cannot take down a node.

**Prevention.** cgroup memory enforcement (already on); teach users to size
`--mem` from `sacct -o MaxRSS` of a past run.

---

## 6. Job killed at its time limit

**Symptom.** A long job "randomly dies" near a round number of minutes.

**Diagnosis.**
```
$ hd sacct -j <id> -X -o JobID,State
State=TIMEOUT
```

**Root cause.** The job ran past `--time` (here one minute). `OverTimeLimit=0`
and `KillWait=30` mean Slurm kills it promptly at the limit.

**Fix.** Re-submit with a longer `--time`, within the partition maximum.

**Prevention.** Set realistic `--time`; partitions cap it (`cpu` 2 h, `gpu` 4 h),
so a typo cannot hold the cluster forever.

---

## 7. `/shared` full, a checkpoint write fails (by hand)

**Symptom.** A training job dies while writing a checkpoint.

**Diagnosis.**
```
$ dd if=/dev/zero of=/shared/ckpt/ckpt.bin bs=1M count=64
dd: error writing '/shared/ckpt/ckpt.bin': No space left on device
$ df -h /shared        # 100% used
```
The job's own error may be vaguer ("write failed"); `df` and the ENOSPC in the
system log are the real signal.

**Root cause.** The shared file system is full, usually old checkpoints.

**Fix.** Delete old checkpoints or grow the export, then `df` shows free space.

**Prevention.** The `SharedStorageLow` alert fires at under 10% free, before jobs
start failing; a checkpoint-retention policy keeps `/shared/ckpt` from filling.

---

## 8. `slurmdbd` stopped: accounting fails, jobs keep running (by hand)

**Symptom.** `sacct` and `sshare` error out; users worry the cluster is down. It
is not.

**Diagnosis.**
```
$ hd sacct -j 1
sacct: error: slurm_persist_conn_open_without_init: failed to open persistent
       connection to host:head:6819: Connection refused
sacct: error: Problem talking to the database: Connection refused
```
Meanwhile a freshly submitted job still runs to completion:
```
$ hd scontrol show job 111 | grep -o 'JobState=[^ ]*'
JobState=COMPLETED
```

**Root cause.** `slurmdbd` (or the database) is down. Scheduling lives in
`slurmctld`, which keeps working; only accounting and fair share depend on the
database.

**Fix.** Restart `slurmdbd`; it reconnects and the queued accounting records
flush:
```
$ onnode head supervisorctl start slurmdbd
after restart, sacct works again.
```

**Prevention.** `autorestart` on slurmdbd; alert on the head node's exporter; know
that scheduling survives a database outage so you do not panic.

---

## 9. GPU job runs at ~0% utilisation

**Symptom.** A GPU job holds the card for a long time but makes little progress;
other GPU jobs wait.

**Diagnosis.**
```
$ hd squeue -j <id> -o '%T on %N, gres %b'
RUNNING on g1, gres gres/gpu:1
$ onnode g1 nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader
1 %
```
Prometheus has both facts, so the alert catches it:
```
gpu_utilization_percent   => 1
slurm_gpu_jobs_running    => 1
# IdleGPUAllocation: gpu_utilization_percent < 10 and on() slurm_gpu_jobs_running > 0  -> 1 series
```

**Root cause.** The job holds the GPU but feeds it nothing. In real training this
is almost always a data loader with `num_workers=0`: the CPU cannot keep the GPU
fed.

**Fix.** Set `num_workers>0` (and prefetch), or stream the data as shards (see the
small-file benchmark). The GPU utilisation jumps and the job finishes far sooner.

**Prevention.** The `IdleGPUAllocation` alert fires after ten minutes of a held
but idle GPU, the most common waste on a shared GPU node.

---

## 10. Fair share: a heavy user yields to a light one

**Symptom.** One account has been running all day; another submits and expects to
wait behind the long queue, but its jobs start first.

**Diagnosis.**
```
$ hd squeue -u bob   -t PENDING -o '%Q' | sort -rn | head -1
7500
$ hd squeue -u carol -t PENDING -o '%Q' | sort -rn | head -1
15000
$ hd sshare -o Account,RawShares,RawUsage,FairShare
 lab-a  60  30  ...     # bob's account, has used the cluster
 lab-b  40   0  ...     # carol's account, under-served
```
carol's pending jobs (priority 15000) outrank bob's (7500) because bob's account
(`lab-a`) has accrued usage while carol's (`lab-b`) has not.

**Root cause.** None: this is fair share working. `priority/multifactor` with
`PriorityWeightFairshare=10000` lifts the under-served account.

**Fix.** Nothing. If the balance is wrong, adjust the accounts' shares with
`sacctmgr modify account ... set Fairshare=...`.

**Prevention.** Set shares to match each group's entitlement; `PriorityDecayHalfLife`
controls how fast past usage is forgiven (one day here).
