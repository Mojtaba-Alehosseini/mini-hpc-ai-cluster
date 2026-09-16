#!/bin/bash
# IO benchmark: fio on /shared (NFS) versus /local (node-local ext4 volume),
# run from c1. Sequential 1 MiB (1 and 4 jobs) and random 4 KiB (queue depth
# 16), direct IO, three trials. Writes one CSV; the report tables are generated
# from it. Small defaults so it is quick; set SIZE and TRIALS for real numbers.
#
#   SIZE=2g TRIALS=3 bench/io/run.sh
#
# Column meaning: value is MBps for the sequential tests, IOPS for the random
# test; latency is the completion latency of one IO in milliseconds.
set -u
cd "$(dirname "$0")/../.."
SIZE=${SIZE:-256m}
TRIALS=${TRIALS:-3}
RUNTIME=${RUNTIME:-20}
OUT=${1:-bench/results/fio.csv}
mkdir -p "$(dirname "$OUT")"

c1() { docker compose exec -T c1 "$@"; }
c1 bash -c 'mkdir -p /shared/benchtmp /local/benchtmp' || {
    echo "cannot reach c1 or the mounts; is the cluster up?" >&2; exit 1; }

echo "fs,test,jobs,trial,metric,value,lat_ms_p50,lat_ms_p99" > "$OUT"

# one fio run -> one CSV row
run() {  # run <fs> <dir> <test> <rw> <bs> <jobs> <iodepth> <engine> <metric> <trial>
    local label=$1 dir=$2 test=$3 rw=$4 bs=$5 nj=$6 qd=$7 eng=$8 metric=$9 trial=${10}
    c1 fio --name="$test" --directory="$dir/benchtmp" --rw="$rw" --bs="$bs" \
        --size="$SIZE" --numjobs="$nj" --iodepth="$qd" --direct=1 \
        --ioengine="$eng" --group_reporting=1 --runtime="$RUNTIME" \
        --time_based=1 --ramp_time=2 --output-format=json 2>/dev/null \
      | python3 bench/io/parse_fio.py "$label" "$test" "$nj" "$trial" "$metric"
    c1 bash -c "rm -f $dir/benchtmp/*"
}

for pair in "shared:/shared" "local:/local"; do
    label=${pair%%:*}; dir=${pair##*:}
    for trial in $(seq "$TRIALS"); do
        echo "== $label trial $trial ==" >&2
        run "$label" "$dir" seqwrite   write    1m 1  1  psync  MBps "$trial" >> "$OUT"
        run "$label" "$dir" seqwrite4  write    1m 4  1  psync  MBps "$trial" >> "$OUT"
        run "$label" "$dir" seqread    read     1m 1  1  psync  MBps "$trial" >> "$OUT"
        run "$label" "$dir" seqread4   read     1m 4  1  psync  MBps "$trial" >> "$OUT"
        run "$label" "$dir" randread   randread 4k 1  16 libaio IOPS "$trial" >> "$OUT"
    done
done

echo "wrote $OUT" >&2
c1 bash -c 'rm -rf /shared/benchtmp /local/benchtmp' 2>/dev/null
column -s, -t "$OUT" | sed -n '1,8p' >&2
