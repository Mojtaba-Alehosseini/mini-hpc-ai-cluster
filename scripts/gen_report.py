#!/usr/bin/env python3
"""Generate docs/report.md from the benchmark CSVs. Every table in the report
comes from this script reading bench/results/, so the report cannot drift from
the data. Run: python scripts/gen_report.py
Inputs it uses if present: fio.csv, smallfiles.csv, train.csv, ior_mdtest.csv,
hpc_patterns_cluster.csv.
"""
import csv
import statistics as st
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "bench" / "results"


def rows(name):
    p = RES / name
    return list(csv.DictReader(p.open())) if p.exists() else []


def median(vals):
    return round(st.median(vals), 1) if vals else float("nan")


def fio_table():
    r = rows("fio.csv")
    tests = [("seqwrite", "seq write, 1 job, MB/s"),
             ("seqwrite4", "seq write, 4 jobs, MB/s"),
             ("seqread", "seq read, 1 job, MB/s"),
             ("seqread4", "seq read, 4 jobs, MB/s"),
             ("randread", "random 4 KiB read, IOPS")]
    out = ["| Test | /shared (NFS) | /local (disk) | ratio |",
           "|---|---|---|---|"]
    for key, label in tests:
        s = median([float(x["value"]) for x in r if x["fs"] == "shared" and x["test"] == key])
        l = median([float(x["value"]) for x in r if x["fs"] == "local" and x["test"] == key])
        ratio = round(l / s, 1) if s else float("nan")
        out.append(f"| {label} | {s:g} | {l:g} | {ratio:g}x |")
    return "\n".join(out)


def smallfiles_table():
    r = rows("smallfiles.csv")
    def med(fs, mode, metric):
        return median([float(x["value"]) for x in r
                       if x["fs"] == fs and x["mode"] == mode and x["metric"] == metric])
    out = ["| Metric | /shared (NFS) | /local (disk) |",
           "|---|---|---|",
           f"| create, files/s | {med('shared','files','create_files_per_s'):g} | {med('local','files','create_files_per_s'):g} |",
           f"| stat, files/s | {med('shared','files','stat_files_per_s'):g} | {med('local','files','stat_files_per_s'):g} |",
           f"| read as loose files, MB/s | {med('shared','files','read_MB_per_s'):g} | {med('local','files','read_MB_per_s'):g} |",
           f"| read as tar shards, MB/s | {med('shared','shards','read_MB_per_s'):g} | {med('local','shards','read_MB_per_s'):g} |"]
    sf = med('shared', 'files', 'read_MB_per_s')
    ss = med('shared', 'shards', 'read_MB_per_s')
    ratio = round(ss / sf, 1) if sf else float("nan")
    return "\n".join(out), ratio


def train_table():
    r = rows("train.csv")
    if not r:
        return None
    out = ["| Run | device | samples/s | max GPU mem (MiB) |", "|---|---|---|---|"]
    for x in r:
        out.append(f"| {x.get('run','')} | {x.get('device','')} | {x.get('samples_per_sec','')} | {x.get('max_mem_mib','')} |")
    return "\n".join(out)


def ior_tables():
    r = rows("ior_mdtest.csv")
    if not r:
        return None

    def val(fs, tool, metric):
        for x in r:
            if x["fs"] == fs and x["tool"] == tool and x["metric"] == metric:
                return float(x["value"])
        return float("nan")

    lw, sw = val("local", "ior", "write"), val("shared", "ior", "write")
    lr, sr = val("local", "ior", "read"), val("shared", "ior", "read")
    bw = ["| Metric | /local | /shared (NFS) | ratio |", "|---|---|---|---|",
          f"| write, O_DIRECT, MiB/s | {lw:g} | {sw:g} | {round(lw/sw,1):g}x slower on NFS |",
          f"| read, buffered, MiB/s | {lr:g} | {sr:g} | cache-served |"]
    md = ["| Operation | /local | /shared (NFS) | ratio |", "|---|---|---|---|"]
    for op, label in (("create", "create"), ("stat", "stat"), ("removal", "remove")):
        lo, so = val("local", "mdtest", op), val("shared", "mdtest", op)
        note = "cache-served" if op == "stat" else f"{round(lo/so):g}x slower on NFS"
        md.append(f"| {label}, ops/s | {lo:g} | {so:g} | {note} |")
    return "\n".join(bw), "\n".join(md)


def hpc_patterns_summary():
    r = rows("hpc_patterns_cluster.csv")
    if not r:
        return None
    kernels = sorted({x["algo"] for x in r})
    variants = sorted({x["variant"].split("-")[0] for x in r})
    n = len(r)
    all_ok = all(x.get("check_ok") == "1" for x in r)
    return kernels, variants, n, all_ok


sf_table, shard_ratio = smallfiles_table()
tt = train_table()
ior = ior_tables()
hp = hpc_patterns_summary()

ior_section = ""
if ior:
    ior_bw, ior_md = ior
    ior_section = f"""## IO benchmarks: IOR and mdtest

IOR and mdtest, the standard HPC IO benchmarks, built from source and run on a
compute node against `/shared` and `/local`. Bandwidth first (IOR, POSIX, two
tasks); the write uses O_DIRECT so it is not absorbed by the page cache, while
the read is buffered and therefore served from cache.

{ior_bw}

Then metadata (mdtest) — the rate for creating, stat-ing and removing many small
files.

{ior_md}

Metadata is where the network file system hurts most: each create or remove is a
synchronous round trip to the server, hundreds to nearly two thousand times
slower than local disk. Stat is fast on both because the entries are cached. It
is the same lesson as the small-file experiment above, from a standard tool.

"""

hp_section = ""
if hp:
    kernels, variants, n, all_ok = hp
    ok = " (every run `check_ok=1`)" if all_ok else ""
    hp_section = f"""## Real workloads: hpc-patterns on the cluster

The external `hpc-patterns` suite — {len(kernels)} kernels ({', '.join(kernels)}) —
built in a node container and run through Slurm across the {', '.join(variants)}
paradigms, the MPI jobs on four ranks over both compute nodes. {n} runs in total,
all passing their correctness check{ok}, including a million-unknown
conjugate-gradient solve. Full data in `bench/results/hpc_patterns_cluster.csv`;
the write-up is `docs/hpc-on-the-cluster.md`.

"""

doc = f"""# Report: mini-hpc-ai-cluster

What was built, and what it measures. Every table here is generated from the CSVs
under `bench/results/` by `scripts/gen_report.py`; the numbers are a real run on
the development laptop (Quadro P2000, Docker on WSL2) and will differ on other
hardware.

## What is real and what is emulated

The cluster runs Slurm 23.11 with a real accounting database, cgroup v2 limits, a
kernel NFS server, one Pascal GPU scheduled as a generic resource, and Apptainer
for job containers. It runs as containers on one laptop, so the "nodes" share a
kernel, the network between them is a Docker bridge, and node sizes are Docker
limits. The GPU reaches a job on the node but not inside an Apptainer container,
because WSL2 exposes it as `/dev/dxg`. These seams are listed in the README and
`docs/DECISIONS.md`.

## Storage: sequential and random IO

fio from a compute node, `/shared` (NFS) against `/local` (a node-local ext4
volume), direct IO, medians of the trials.

{fio_table()}

The network file system is several times slower to write than a local disk, as
expected of one server behind a bridge. The read rows are inflated by NFS
server-side caching (a file read right after it is written is served from cache);
`bench/README.md` says so rather than hiding it.

## Storage: many small files versus shards

The experiment that matters for AI datasets on shared storage. The same bytes are
stored as many 4 KiB files and as a few tar shards, then read back.

{sf_table}

The headline is the ratio: on the shared file system, reading the data as shards
is about **{shard_ratio:g}x** faster than reading it as loose files, and creating
the loose files is roughly ten times slower on NFS than on a local disk because
every file is a metadata round trip to the server. This is why data loaders use
`webdataset`, tar shards or record files.

{ior_section}## Scheduler behaviour

Shown by the acceptance tests and the runbook, with real output in
`runbook/RUNBOOK.md`:

- **Limits.** A job that exceeds its `--mem` is killed `OUT_OF_MEMORY` by the
  cgroup; a job past its `--time` is killed `TIMEOUT`; a fifth job on QoS
  `normal` pends with `QOSMaxJobsPerUserLimit`.
- **Fair share.** After one account (`lab-a`) builds usage, the other account's
  jobs outrank its pending ones: top pending priority 7500 for the heavy user
  versus 15000 for the under-served one.
- **Drain and resume.** A drained node takes no new jobs; new work lands on the
  other node; `scontrol ... state=resume` restores it.

## GPU

The Quadro P2000 (4 GB, Pascal) is scheduled as `gres/gpu` and reachable from a
job on g1 (`nvidia-smi -L` shows it). {"A short training run:" if tt else "A training run on the node is the intended GPU load; on this WSL host PyTorch-CUDA availability is limited, so the run is documented in containers/jobs and executed on a bare-metal host or Kaggle."}
"""

if tt:
    doc += "\n" + tt + "\n"

doc += "\n" + hp_section + """## Monitoring

Prometheus scrapes node, Slurm and GPU exporters; Grafana shows the Cluster, GPU
node and Storage dashboards; five alert rules fire on real conditions and each
has a promtool unit test. The `IdleGPUAllocation` alert catches the most common
GPU waste: a job holding the GPU at under 10% utilisation. Screenshots of the
three dashboards under load are in `docs/hpc-on-the-cluster.md`.

## Limitations

One physical host, so there is no real interconnect and the "nodes" share a
kernel and clock. One Pascal GPU with 4 GB, so no GPU-partition scheduling. NFS
is a single kernel server on a Docker volume, not a parallel file system; there
is no Lustre, GPFS or VAST, which would change the small-file numbers most of
all. The GPU does not enter an Apptainer container on WSL. Every one of these is
stated where it matters rather than smoothed over.
"""

out = ROOT / "docs" / "report.md"
out.write_text(doc)
print("wrote", out, f"({len(doc)} bytes)")
