#!/bin/bash
# Container start. This does only what must happen in the init process: create
# the run and log directories the daemons need, and, on a compute node, set up
# cgroup v2 delegation. Everything else (munge key, Slurm config, users,
# accounts, starting the daemons) is done by Ansible, so the daemons are left
# stopped here (autostart is off in the supervisord config).
# NODE_ROLE is "head" or "compute".
set -euo pipefail

role="${NODE_ROLE:-compute}"

mkdir -p /run/munge /var/log/munge \
         /run/slurm /var/log/slurm \
         /var/spool/slurmctld /var/spool/slurmd /etc/slurm
chown munge:munge /run/munge /var/log/munge
chown slurm:slurm /run/slurm /var/log/slurm /var/spool/slurmctld

# cgroup v2 for compute nodes. Docker starts this process at the root of the
# container's cgroup namespace, which is a delegated cgroup. A cgroup that has
# processes in it cannot hand controllers to child cgroups (the "no internal
# processes" rule), so move ourselves into init.scope first, then enable the
# controllers, then create system.slice, where Slurm's cgroup/v2 plugin (with
# IgnoreSystemd=yes) builds <node>_slurmstepd.scope. Processes started later by
# "docker exec" or supervisord inherit PID 1's cgroup, so they land here too.
if [ "$role" = "compute" ] && [ -w /sys/fs/cgroup/cgroup.subtree_control ]; then
    mkdir -p /sys/fs/cgroup/init.scope /sys/fs/cgroup/system.slice
    echo $$ > /sys/fs/cgroup/init.scope/cgroup.procs
    echo "+cpuset +cpu +memory +pids" > /sys/fs/cgroup/cgroup.subtree_control
    echo "+cpuset +cpu +memory +pids" > /sys/fs/cgroup/system.slice/cgroup.subtree_control
fi

exec /usr/bin/supervisord -n -c "/opt/supervisor/$role.conf"
