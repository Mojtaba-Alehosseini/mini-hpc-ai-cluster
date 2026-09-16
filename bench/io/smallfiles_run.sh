#!/bin/bash
# Host wrapper: run the small-file experiment inside c1 against /shared (NFS)
# and /local (node disk), collect one CSV. The script itself is piped in, so
# nothing has to be copied into the container.
set -u
cd "$(dirname "$0")/../.."
NFILES=${NFILES:-20000}
TRIALS=${TRIALS:-3}
OUT=${1:-bench/results/smallfiles.csv}
mkdir -p "$(dirname "$OUT")"
echo "fs,mode,metric,trial,value" > "$OUT"
for pair in "shared:/shared" "local:/local"; do
    label=${pair%%:*}; dir=${pair##*:}
    echo "== small files on $label ==" >&2
    docker compose exec -T \
        -e DIR="$dir" -e LABEL="$label" -e NFILES="$NFILES" -e TRIALS="$TRIALS" \
        c1 bash -s < bench/io/smallfiles.sh >> "$OUT"
done
echo "wrote $OUT" >&2
column -s, -t "$OUT" >&2
