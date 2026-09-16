#!/usr/bin/env python3
"""Slurm metrics exporter. Runs on the head node, calls sinfo/squeue/scontrol,
and serves Prometheus metrics on :9200. Small and readable on purpose: it is the
metrics the dashboards and alerts actually use, not a full mirror of Slurm.

Metrics:
  slurm_up                                  1 if the controller answers
  slurm_nodes{state=...}                    node count by base state (idle/mix/alloc/down/drain)
  slurm_jobs{state=...}                     job count by state (running/pending)
  slurm_partition_cpus{partition,kind=...}  CPUs allocated/idle/other/total per partition
  slurm_gpu_jobs_running                    running jobs in the gpu partition (for the idle-GPU alert)
"""
from __future__ import annotations
import subprocess
import time
from collections import Counter
from http.server import BaseHTTPRequestHandler, HTTPServer
from prometheus_client import REGISTRY, Gauge, generate_latest

UP = Gauge("slurm_up", "1 if slurmctld answers")
NODES = Gauge("slurm_nodes", "nodes by base state", ["state"])
JOBS = Gauge("slurm_jobs", "jobs by state", ["state"])
PART_CPUS = Gauge("slurm_partition_cpus", "CPUs per partition by kind", ["partition", "kind"])
GPU_JOBS = Gauge("slurm_gpu_jobs_running", "running jobs in the gpu partition")


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=15).stdout


def collect():
    try:
        UP.set(1 if "is UP" in run(["scontrol", "ping"]) else 0)
    except Exception:
        UP.set(0)
        return

    # nodes by base state: strip trailing markers like * ~ # from %t
    states = Counter()
    for line in run(["sinfo", "-h", "-N", "-o", "%t"]).split():
        states[line.strip("*~#$@")] += 1
    for s in ("idle", "mix", "alloc", "down", "drain", "resv"):
        NODES.labels(state=s).set(states.get(s, 0))

    # jobs by state
    jobs = Counter(run(["squeue", "-h", "-o", "%T"]).split())
    for s in ("RUNNING", "PENDING"):
        JOBS.labels(state=s.lower()).set(jobs.get(s, 0))

    # CPUs per partition: %C is Allocated/Idle/Other/Total
    for line in run(["sinfo", "-h", "-o", "%R %C"]).splitlines():
        parts = line.split()
        if len(parts) != 2 or "/" not in parts[1]:
            continue
        name, aiot = parts
        a, i, o, t = (int(x) for x in aiot.split("/"))
        for kind, val in (("alloc", a), ("idle", i), ("other", o), ("total", t)):
            PART_CPUS.labels(partition=name, kind=kind).set(val)

    # running jobs on the gpu partition
    gpu = [l for l in run(["squeue", "-h", "-t", "RUNNING", "-p", "gpu", "-o", "%i"]).split()]
    GPU_JOBS.set(len(gpu))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404); self.end_headers(); return
        collect()
        out = generate_latest(REGISTRY)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.end_headers()
        self.wfile.write(out)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 9200), Handler).serve_forever()
