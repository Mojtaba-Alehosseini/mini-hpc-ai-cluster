#!/usr/bin/env python3
"""GPU metrics exporter for the g1 node. Serves Prometheus metrics on :9400.

It reads the GPU with `nvidia-smi`, not pynvml: on WSL2 the GPU is reached
through /dev/dxg and the driver libraries under /usr/lib/wsl, and nvidia-smi
handles that where a bare pynvml load does not. On a bare-metal host either would
work. Adapted from the gpu-cost-energy-dashboard exporter.

It also reads a training-progress file if a job writes one
(/shared/ckpt/gpu_train.prom, "samples_per_sec <value>"), so the dashboard can
show throughput and the idle-GPU alert has something to compare against.
"""
from __future__ import annotations
import subprocess
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from prometheus_client import REGISTRY, Gauge, generate_latest

UTIL = Gauge("gpu_utilization_percent", "GPU compute utilisation (%)", ["gpu"])
POWER = Gauge("gpu_power_watts", "GPU power draw (W)", ["gpu"])
TEMP = Gauge("gpu_temperature_celsius", "GPU temperature (C)", ["gpu"])
MEM_USED = Gauge("gpu_memory_used_mib", "GPU memory used (MiB)", ["gpu"])
MEM_TOTAL = Gauge("gpu_memory_total_mib", "GPU memory total (MiB)", ["gpu"])
CLOCK = Gauge("gpu_clock_sm_mhz", "GPU SM clock (MHz)", ["gpu"])
SAMPLES = Gauge("gpu_training_samples_per_sec", "training throughput, set by a job", ["gpu"])
UP = Gauge("gpu_exporter_up", "1 if nvidia-smi could be read")

QUERY = "index,utilization.gpu,power.draw,temperature.gpu,memory.used,memory.total,clocks.sm"
TRAIN_FILE = Path("/shared/ckpt/gpu_train.prom")


def num(s: str) -> float:
    # nvidia-smi prints "[N/A]" for fields a GPU does not report (the P2000 on
    # WSL does not report power); treat those as 0 rather than crashing.
    try:
        return float(s)
    except (TypeError, ValueError):
        return 0.0


def collect():
    try:
        out = subprocess.run(
            ["nvidia-smi", f"--query-gpu={QUERY}", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=10).stdout.strip()
    except Exception:
        UP.set(0)
        return
    UP.set(0 if not out else 1)
    for line in out.splitlines():
        f = [x.strip() for x in line.split(",")]
        if len(f) < 7:
            continue
        g = f[0]
        UTIL.labels(gpu=g).set(num(f[1]))
        POWER.labels(gpu=g).set(num(f[2]))
        TEMP.labels(gpu=g).set(num(f[3]))
        MEM_USED.labels(gpu=g).set(num(f[4]))
        MEM_TOTAL.labels(gpu=g).set(num(f[5]))
        CLOCK.labels(gpu=g).set(num(f[6]))
    # optional training throughput
    sps = 0.0
    try:
        for line in TRAIN_FILE.read_text().splitlines():
            if line.startswith("samples_per_sec"):
                sps = float(line.split()[1])
    except Exception:
        pass
    SAMPLES.labels(gpu="0").set(sps)


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
    HTTPServer(("0.0.0.0", 9400), Handler).serve_forever()
