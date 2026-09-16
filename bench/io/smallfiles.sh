#!/bin/bash
# Small-file experiment. Runs inside a compute node (piped in with bash -s).
# It compares the same bytes stored two ways on the shared file system:
#   - as many tiny files (the shape of an unpacked image dataset)
#   - as a few tar shards (the shape a data loader should use)
# The shared file system is slow at the first because every file is a metadata
# round trip to the NFS server; the shards turn that into a few big streaming
# reads. This prints CSV rows to stdout:
#     fs,mode,metric,trial,value
# metric is files_per_s (create, stat, read) or MB_per_s (shard read).
set -u
DIR=${DIR:-/shared}
NFILES=${NFILES:-20000}
NDIRS=${NDIRS:-200}
PERSHARD=${PERSHARD:-1000}
FSIZE=${FSIZE:-4096}
TRIALS=${TRIALS:-3}
label=${LABEL:-shared}
base="$DIR/smallfiles_exp"

now() { date +%s.%N; }
elapsed() { echo "$(now) $1" | awk '{printf "%.3f", $1-$2}'; }
drop_caches() { sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true; }

for trial in $(seq "$TRIALS"); do
    rm -rf "$base"; mkdir -p "$base/files" "$base/shards"

    # create NFILES files of FSIZE bytes across NDIRS directories
    t=$(now)
    perdir=$(( NFILES / NDIRS ))
    for d in $(seq 1 "$NDIRS"); do
        dir="$base/files/d$d"; mkdir -p "$dir"
        for f in $(seq 1 "$perdir"); do
            head -c "$FSIZE" /dev/zero > "$dir/f$f.bin"
        done
    done
    echo "$label,files,create_files_per_s,$trial,$(awk -v n="$NFILES" -v e="$(elapsed "$t")" 'BEGIN{printf "%.0f", n/e}')"

    # metadata walk: stat every file
    drop_caches
    t=$(now)
    find "$base/files" -type f -printf '' 2>/dev/null
    n=$(find "$base/files" -type f | wc -l)
    echo "$label,files,stat_files_per_s,$trial,$(awk -v n="$n" -v e="$(elapsed "$t")" 'BEGIN{printf "%.0f", n/e}')"

    # sequential read of every small file
    drop_caches
    t=$(now)
    bytes=$(find "$base/files" -type f -exec cat {} + | wc -c)
    echo "$label,files,read_files_per_s,$trial,$(awk -v n="$n" -v e="$(elapsed "$t")" 'BEGIN{printf "%.0f", n/e}')"
    echo "$label,files,read_MB_per_s,$trial,$(awk -v b="$bytes" -v e="$(elapsed "$t")" 'BEGIN{printf "%.1f", b/1e6/e}')"

    # pack the same bytes into tar shards of PERSHARD files each
    i=0; shard=0
    for d in "$base"/files/d*; do
        tar -cf "$base/shards/shard$shard.tar" -C "$d" . 2>/dev/null
        shard=$(( shard + 1 ))
    done

    # sequential read of the shards
    drop_caches
    t=$(now)
    sbytes=$(cat "$base"/shards/*.tar | wc -c)
    echo "$label,shards,read_MB_per_s,$trial,$(awk -v b="$sbytes" -v e="$(elapsed "$t")" 'BEGIN{printf "%.1f", b/1e6/e}')"

    rm -rf "$base"
done
