#!/usr/bin/env bash
# Build IOR and mdtest from source in a node container and run them on the
# shared NFS export (/shared) against a node-local disk (/local, on c1).
#
# IOR measures bandwidth; mdtest measures metadata (create/stat/remove) rates.
# The write figure uses O_DIRECT so it is not absorbed by the page cache; the
# read figure is buffered and therefore served from cache (stated, not hidden).
# The results in bench/results/ior_mdtest.csv were produced by this script.
#
# Usage: bench/io/ior_mdtest.sh
set -euo pipefail
COMPOSE=${COMPOSE:-docker compose}

$COMPOSE exec -T c1 bash -lc '
  set -e
  export DEBIAN_FRONTEND=noninteractive
  if [ ! -x /root/ior/src/ior ]; then
    apt-get update -qq >/dev/null
    apt-get install -y -qq git autoconf automake libtool make pkg-config ca-certificates >/dev/null
    cd /root && rm -rf ior && git clone -q --depth 1 https://github.com/hpc/ior
    cd /root/ior && ./bootstrap >/dev/null && ./configure MPICC=mpicc >/dev/null && make -j2 >/dev/null
  fi
  cd /root/ior
  mp="mpirun --allow-run-as-root --oversubscribe -np 2"
  for fs in local shared; do
    d="/$fs/iortmp"; mkdir -p "$d"
    echo "### IOR $fs ###"
    $mp src/ior -a POSIX --posix.odirect -b 128m -t 2m -w -F -o "$d/f" 2>/dev/null | grep -E "^write" | head -1
    $mp src/ior -a POSIX             -b 128m -t 2m -w -r -F -o "$d/f" 2>/dev/null | grep -E "^read"  | head -1
    rm -rf "$d"
    echo "### mdtest $fs ###"
    $mp src/mdtest -n 600 -F -d "/$fs/mdtmp" 2>/dev/null | grep -E "File creation|File stat|File removal"
    rm -rf "/$fs/mdtmp"
  done
'
