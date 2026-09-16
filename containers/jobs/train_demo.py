#!/usr/bin/env python3
"""A short CNN training run, used as the GPU load for the monitoring dashboards.
It trains a small conv net on synthetic 64x64 images (no dataset download), on
the GPU if one is usable and on the CPU otherwise. It reports throughput
(samples/sec) and peak GPU memory, and writes a Prometheus textfile the GPU
exporter reads (/shared/ckpt/gpu_train.prom) so the dashboard shows live
samples/sec. A row is appended to bench/results/train.csv via stdout capture.

Runs directly on the node (not under Apptainer): on WSL the GPU is /dev/dxg and
does not enter an Apptainer container. Usage: python train_demo.py [steps]
"""
import sys
import time
from pathlib import Path

import torch
import torch.nn as nn

STEPS = int(sys.argv[1]) if len(sys.argv) > 1 else 300
BATCH = 64
PROM = Path("/shared/ckpt/gpu_train.prom")

device = "cuda" if torch.cuda.is_available() else "cpu"
name = torch.cuda.get_device_name(0) if device == "cuda" else "cpu"


class SmallNet(nn.Module):
    def __init__(self, classes=10):
        super().__init__()
        self.net = nn.Sequential(
            nn.Conv2d(3, 32, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
            nn.Conv2d(32, 64, 3, padding=1), nn.ReLU(), nn.MaxPool2d(2),
            nn.Conv2d(64, 128, 3, padding=1), nn.ReLU(), nn.AdaptiveAvgPool2d(1),
            nn.Flatten(), nn.Linear(128, classes))

    def forward(self, x):
        return self.net(x)


def write_prom(sps, step):
    try:
        PROM.parent.mkdir(parents=True, exist_ok=True)
        PROM.write_text(f"samples_per_sec {sps:.1f}\ntrain_step {step}\n")
    except Exception:
        pass


def main():
    torch.manual_seed(0)
    model = SmallNet().to(device)
    opt = torch.optim.SGD(model.parameters(), lr=0.01, momentum=0.9)
    loss_fn = nn.CrossEntropyLoss()
    x = torch.randn(BATCH, 3, 64, 64, device=device)
    y = torch.randint(0, 10, (BATCH,), device=device)

    # warm up
    for _ in range(5):
        opt.zero_grad(); loss_fn(model(x), y).backward(); opt.step()
    if device == "cuda":
        torch.cuda.synchronize(); torch.cuda.reset_peak_memory_stats()

    t0 = time.time()
    for step in range(1, STEPS + 1):
        opt.zero_grad()
        loss = loss_fn(model(x), y)
        loss.backward()
        opt.step()
        if step % 20 == 0:
            if device == "cuda":
                torch.cuda.synchronize()
            sps = step * BATCH / (time.time() - t0)
            write_prom(sps, step)
            print(f"step {step:4d}  samples/s {sps:8.1f}  loss {loss.item():.3f}", flush=True)

    if device == "cuda":
        torch.cuda.synchronize()
    sps = STEPS * BATCH / (time.time() - t0)
    max_mib = int(torch.cuda.max_memory_allocated() / 2**20) if device == "cuda" else 0
    write_prom(sps, STEPS)
    # machine-readable summary line for bench/results/train.csv
    print(f"CSV,{name.replace(',', ' ')},{sps:.1f},{max_mib}", flush=True)


if __name__ == "__main__":
    main()
