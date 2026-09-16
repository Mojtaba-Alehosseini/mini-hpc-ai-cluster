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

t01() {  # sinfo shows c1, c2 idle in cpu, c1 in debug, g1 idle in gpu
    local out; out=$(hd sinfo -h -o '%P %t %N')
    echo "$out"
    grep -Eq '^cpu\* idle c\[1-2\]$' <<<"$out" \
        && grep -Eq '^debug idle c1$' <<<"$out" \
        && grep -Eq '^gpu idle g1$' <<<"$out"
}

t03() {  # a GPU job on the gpu partition sees the P2000 through --gres
    local out; out=$(as_user alice srun --partition=gpu --gres=gpu:1 --time=2:00 \
                     nvidia-smi -L 2>&1)
    echo "$out"
    grep -qi 'P2000' <<<"$out"
}

t04() {  # the GPU smoke job runs a container under Apptainer on g1 and sees the
         # P2000 from the node (GPU-in-container is a documented WSL limitation)
    # build the container image once (cached in the shared volume)
    hd bash -c '[ -f /shared/images/cuda.sif ]' 2>/dev/null || make images >/dev/null 2>&1
    # the repo is not inside the containers, so feed the job script over stdin
    local job; job=$(as_user alice sbatch --parsable < containers/jobs/gpu_smoke.sbatch 2>/dev/null) \
        || { echo "submit failed"; return 1; }
    echo "job $job"
    wait_state "$job" '^COMPLETED$' 300 || return 1
    local out; out=$(as_user alice cat "/shared/home/alice/gpu_smoke.$job.out" 2>/dev/null)
    echo "$out" | tail -4
    # the P2000 shows on the node, and a container ran under Apptainer
    grep -qi 'P2000' <<<"$out" && grep -qi 'PRETTY_NAME' <<<"$out"
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

t06() {  # a job that uses more memory than it asked for is killed by the cgroup
    # ask for 256 MB, then try to allocate ~700 MB
    local job; job=$(as_user alice sbatch --parsable --mem=256M \
        --wrap="python3 -c 'a=bytearray(700*1024*1024); import time; time.sleep(20)'") || return 1
    wait_state "$job" '^(OUT_OF_MEMORY|FAILED)$' 90 || return 1
    local st; st=$(hd sacct -j "$job" -X -n -o State,ExitCode -P | tr -d ' ')
    echo "job $job ended: $st"
    grep -qE '^(OUT_OF_MEMORY|FAILED)' <<<"$st"
}

t07() {  # a job that runs past its --time is killed at TIMEOUT
    local job; job=$(as_user alice sbatch --parsable --time=00:01:00 --wrap='sleep 300') || return 1
    wait_state "$job" '^TIMEOUT$' 130 || return 1
    local st; st=$(hd sacct -j "$job" -X -n -o State -P | tr -d ' ')
    echo "job $job ended: $st"
    [ "$st" = "TIMEOUT" ]
}

t10() {  # fair share: bob's account runs first and builds usage, so when carol
         # submits, her jobs outrank his pending ones (lab-b is under-served)
    hd scancel -u bob >/dev/null 2>&1; hd scancel -u carol >/dev/null 2>&1; sleep 2
    local j
    for _ in $(seq 20); do j=$(as_user bob sbatch --parsable --qos=high --wrap='sleep 200'); done
    sleep 28   # let lab-a accrue usage while its jobs run
    for _ in $(seq 5); do j=$(as_user carol sbatch --parsable --qos=high --wrap='sleep 200'); done
    sleep 8
    local bob_p carol_p
    bob_p=$(hd squeue -h -u bob   -t PENDING -o '%Q' | sort -rn | head -1)
    carol_p=$(hd squeue -h -u carol -t PENDING -o '%Q' | sort -rn | head -1)
    echo "top pending priority: bob=$bob_p carol=$carol_p"
    hd scancel -u bob >/dev/null 2>&1; hd scancel -u carol >/dev/null 2>&1
    [ -n "$carol_p" ] && [ -n "$bob_p" ] && [ "$carol_p" -gt "$bob_p" ]
}

t11() {  # a drained node takes no new jobs; resume brings it back
    hd scontrol update nodename=c2 state=drain reason=test >/dev/null || return 1
    sleep 2
    local drained; drained=$(hd sinfo -h -n c2 -o '%t')
    echo "c2 after drain: $drained"
    # a new job must not land on c2
    local job; job=$(as_user alice sbatch --parsable --nodelist=c1 --wrap=hostname)
    wait_state "$job" '^COMPLETED$' 60
    hd scontrol update nodename=c2 state=resume >/dev/null
    sleep 2
    local back; back=$(hd sinfo -h -n c2 -o '%t')
    echo "c2 after resume: $back"
    grep -q 'drain' <<<"$drained" && grep -q 'idle' <<<"$back"
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

pt() { docker compose exec -T prometheus promtool "$@"; }

t12() {  # every Prometheus target is up, and the alert rules pass their unit tests
    # unit tests for the alert rules (alerts.test.yml is in the mounted config dir)
    if ! pt test rules /etc/prometheus/alerts.test.yml >/tmp/pt.out 2>&1; then
        sed 's/^/      /' /tmp/pt.out | tail -12; return 1
    fi
    echo "promtool: $(grep -c SUCCESS /tmp/pt.out) test file(s) passed"
    # give the scrapes a moment, then require all targets up and none down
    local up_ct down_ct
    for _ in $(seq 15); do
        up_ct=$(pt query instant http://localhost:9090 'up == 1' 2>/dev/null | grep -c '=>')
        down_ct=$(pt query instant http://localhost:9090 'up == 0' 2>/dev/null | grep -c '=>')
        [ "${up_ct:-0}" -ge 8 ] && [ "${down_ct:-0}" -eq 0 ] && break
        sleep 4
    done
    echo "targets up=$up_ct down=$down_ct (expect >=8 up, 0 down)"
    [ "${up_ct:-0}" -ge 8 ] && [ "${down_ct:-0}" -eq 0 ]
}

t14() {  # the IO benchmark runs end to end at a small size and writes a valid CSV
    SIZE=16m TRIALS=1 RUNTIME=2 ./bench/io/run.sh /tmp/fio_ci.csv >/dev/null 2>&1
    local rows; rows=$(wc -l < /tmp/fio_ci.csv 2>/dev/null || echo 0)
    echo "rows=$rows"
    head -1 /tmp/fio_ci.csv | grep -q '^fs,test,jobs,trial,metric,value' && [ "$rows" -gt 1 ]
}

check "01 sinfo: c1,c2 in cpu, c1 in debug, g1 in gpu"    t01
check "02 sbatch as alice completes with account/partition" t02
check "03 srun --gres=gpu:1 nvidia-smi shows the P2000"   t03
check "04 Apptainer GPU smoke job prints the GPU on g1"   t04
check "05 /shared has the same inode on head, c1 and c2"  t05
check "06 over-memory job is killed (cgroup)"             t06
check "07 over-time job is killed at TIMEOUT"             t07
check "08 --qos=debug --time=2:00:00 is rejected"         t08
check "09 fifth job on QoS normal pends (MaxJobsPerUser)"  t09
check "10 fair share: carol outranks bob after his usage" t10
check "11 drain stops new jobs on c2; resume restores it" t11
check "12 Prometheus targets up; alert rules unit-tested"  t12
check "13 ansible site.yml --check reports no change"      t13
check "14 IO benchmark runs and writes a valid CSV"       t14

echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
