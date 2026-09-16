#!/usr/bin/env python3
"""Turn one fio --output-format=json result (on stdin) into CSV rows.

Usage: parse_fio.py <fs_label> <test> <jobs> <trial> <metric>
where metric is "MBps" (sequential tests) or "IOPS" (random tests). Emits, for
whichever direction did IO:
    fs,test,jobs,trial,metric,value,lat_ms_p50,lat_ms_p99
Latency is the completion latency of one IO, in milliseconds.
"""
import json
import sys


def pctl(clat, want):
    for k, v in clat.get("percentile", {}).items():
        if abs(float(k) - want) < 0.001:
            return round(v / 1e6, 3)  # ns -> ms
    return ""


def main():
    fs, test, jobs, trial, metric = sys.argv[1:6]
    job = json.load(sys.stdin)["jobs"][0]
    for direction in ("read", "write"):
        d = job.get(direction, {})
        if not d or d.get("io_bytes", 0) == 0:
            continue
        if metric == "IOPS":
            value = round(d.get("iops", 0.0), 1)
        else:
            value = round(d.get("bw_bytes", 0) / 1e6, 1)
        clat = d.get("clat_ns", {})
        print(f"{fs},{test},{jobs},{trial},{metric},{value},"
              f"{pctl(clat, 50.0)},{pctl(clat, 99.0)}")


if __name__ == "__main__":
    main()
