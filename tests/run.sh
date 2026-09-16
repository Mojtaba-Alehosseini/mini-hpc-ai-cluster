#!/bin/bash
# Acceptance tests, one function per numbered test in the build plan.
# Run from the repository root on a cluster that "make up" reported ready.
set -u
cd "$(dirname "$0")/.."
pass=0; fail=0
hd() { docker compose exec -T head "$@"; }   # run on the head node
as_user() { local u=$1; shift; docker compose exec -T -u "$u" -w "/shared/home/$u" head "$@"; }

check() {  # check <name> <command...>: pass if the command exits 0
    local name=$1; shift
    if "$@" >/tmp/mhc_test.out 2>&1; then
        echo "PASS  $name"; pass=$((pass+1))
    else
        echo "FAIL  $name"; sed 's/^/      /' /tmp/mhc_test.out | head -20; fail=$((fail+1))
    fi
}

wait_state() {  # wait_state <jobid> <regex of final states> [timeout s]
    local job=$1 want=$2 t=${3:-120} s
    for _ in $(seq "$t"); do
        s=$(hd sacct -j "$job" -X -n -o State -P 2>/dev/null | tr -d ' ')
        [[ "$s" =~ $want ]] && return 0
        [[ "$s" =~ ^(FAILED|CANCELLED|TIMEOUT|OUT_OF_MEMORY|COMPLETED|NODE_FAIL) ]] && { echo "job $job ended as $s"; return 1; }
        sleep 1
    done
    echo "job $job still $s after $t s"; return 1
}

t01() {  # sinfo shows c1, c2 idle in cpu and c1 in debug
    local out; out=$(hd sinfo -h -o '%P %t %N')
    echo "$out"
    grep -Eq '^cpu\* idle c\[1-2\]$' <<<"$out" && grep -Eq '^debug idle c1$' <<<"$out"
}

t02() {  # a job submitted by alice completes with the right account and partition
    local job; job=$(as_user alice sbatch --parsable --wrap=hostname) || return 1
    wait_state "$job" '^COMPLETED$' || return 1
    # slurmctld sets State=COMPLETED a moment before the full accounting record
    # is readable, so poll the combined line until the partition field appears.
    local line
    for _ in $(seq 10); do
        line=$(hd sacct -j "$job" -X -n -o Account,Partition,State,ExitCode -P | tr -d ' ')
        [ "$line" = "lab-a|cpu|COMPLETED|0:0" ] && break
        sleep 1
    done
    echo "job $job: $line"
    [ "$line" = "lab-a|cpu|COMPLETED|0:0" ]
}

t05() {  # /shared is the same file system on every node: a file written on head
         # has the same inode on c1 and c2 (it is one NFS export, not per-node)
    local f=/shared/home/alice/inode_probe.txt
    hd bash -c "echo shared-fs-test > $f" || return 1
    local i_head i_c1 i_c2
    i_head=$(hd stat -c %i "$f")
    i_c1=$(docker compose exec -T c1 stat -c %i "$f" 2>/dev/null)
    i_c2=$(docker compose exec -T c2 stat -c %i "$f" 2>/dev/null)
    echo "inode head=$i_head c1=$i_c1 c2=$i_c2"
    [ -n "$i_head" ] && [ "$i_head" = "$i_c1" ] && [ "$i_c1" = "$i_c2" ]
}

t08() {  # a debug job asking for two hours is rejected at submission
    local out; out=$(as_user alice sbatch --qos=debug --partition=debug --time=2:00:00 --wrap=hostname 2>&1)
    echo "$out"
    grep -q 'Job violates accounting/QOS policy\|time limit' <<<"$out"
}

t09() {  # the fifth job of one user on QoS normal pends with QOSMaxJobsPerUserLimit
    local ids=() j
    for _ in 1 2 3 4 5; do
        j=$(as_user bob sbatch --parsable --qos=normal --wrap='sleep 60') || return 1
        ids+=("$j")
    done
    sleep 5
    local reason; reason=$(hd squeue -h -j "${ids[4]}" -o '%T %r')
    echo "fifth job: $reason"
    hd scancel -u bob >/dev/null 2>&1
    [ "$reason" = "PENDING QOSMaxJobsPerUserLimit" ]
}

t13() {  # the Ansible playbook is idempotent: a second run in check mode
         # reports no change on any host
    local out; out=$(cd ansible && ansible-playbook site.yml --check 2>&1)
    echo "$out" | grep -E 'changed=|failed=' || true
    # every host line must read changed=0 and failed=0
    ! echo "$out" | grep -qE 'changed=[1-9]|failed=[1-9]|unreachable=[1-9]'
}

check "01 sinfo: c1,c2 idle in cpu, c1 in debug"        t01
check "02 sbatch as alice completes with account/partition" t02
check "05 /shared has the same inode on head, c1 and c2"  t05
check "08 --qos=debug --time=2:00:00 is rejected"         t08
check "09 fifth job on QoS normal pends (MaxJobsPerUser)"  t09
check "13 ansible site.yml --check reports no change"      t13

echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
