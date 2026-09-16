#!/usr/bin/env python3
"""Generate the three Grafana dashboards as JSON, from one place so they stay
consistent. Run: python monitoring/grafana/gen_dashboards.py
Writes into monitoring/grafana/dashboards/. The dashboards are provisioned into
Grafana at start; the datasource uid "prometheus" is fixed in provisioning."""
import json
from pathlib import Path

DS = {"type": "prometheus", "uid": "prometheus"}
OUT = Path(__file__).parent / "dashboards"
_id = 0


def pid():
    global _id
    _id += 1
    return _id


def target(expr, legend=""):
    return {"datasource": DS, "expr": expr, "legendFormat": legend, "refId": "A"}


def panel(title, ptype, targets, x, y, w, h, unit=None):
    fc = {"defaults": {"custom": {}}, "overrides": []}
    if unit:
        fc["defaults"]["unit"] = unit
    return {
        "id": pid(), "title": title, "type": ptype, "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [dict(target(e, l), refId=chr(65 + i)) for i, (e, l) in enumerate(targets)],
        "fieldConfig": fc, "options": {},
    }


def dashboard(uid, title, panels):
    return {
        "uid": uid, "title": title, "schemaVersion": 39, "version": 1,
        "editable": True, "refresh": "10s", "tags": ["mini-hpc"],
        "time": {"from": "now-30m", "to": "now"},
        "templating": {"list": []}, "annotations": {"list": []},
        "panels": panels,
    }


# --- Cluster ---------------------------------------------------------------
cluster = dashboard("mini-hpc-cluster", "Cluster", [
    panel("Nodes by state", "timeseries",
          [('slurm_nodes', '{{state}}')], 0, 0, 12, 8),
    panel("Jobs", "timeseries",
          [('slurm_jobs', '{{state}}')], 12, 0, 12, 8),
    panel("CPUs allocated vs total", "timeseries",
          [('sum(slurm_partition_cpus{kind="alloc"})', 'allocated'),
           ('sum(slurm_partition_cpus{kind="total"})', 'total')], 0, 8, 12, 8),
    panel("CPU allocated %", "gauge",
          [('100 * sum(slurm_partition_cpus{kind="alloc"}) / sum(slurm_partition_cpus{kind="total"})', 'cpu %')],
          12, 8, 6, 8, unit="percent"),
    panel("Controller up", "stat",
          [('slurm_up', 'slurmctld')], 18, 8, 6, 8),
])

# --- GPU node --------------------------------------------------------------
gpu = dashboard("mini-hpc-gpu", "GPU node", [
    panel("GPU utilisation %", "timeseries",
          [('gpu_utilization_percent', 'gpu {{gpu}}')], 0, 0, 12, 8, unit="percent"),
    panel("GPU memory used (MiB)", "timeseries",
          [('gpu_memory_used_mib', 'used'), ('gpu_memory_total_mib', 'total')], 12, 0, 12, 8),
    panel("Power (W)", "stat", [('gpu_power_watts', 'W')], 0, 8, 6, 8, unit="watt"),
    panel("Temperature (C)", "stat", [('gpu_temperature_celsius', 'C')], 6, 8, 6, 8, unit="celsius"),
    panel("Training samples/sec", "timeseries",
          [('gpu_training_samples_per_sec', 'samples/s')], 12, 8, 12, 8),
])

# --- Storage ---------------------------------------------------------------
storage = dashboard("mini-hpc-storage", "Storage", [
    panel("Shared export free (bytes)", "timeseries",
          [('node_filesystem_avail_bytes{mountpoint="/exports"}', 'free')], 0, 0, 12, 8, unit="bytes"),
    panel("Shared export free %", "gauge",
          [('100 * node_filesystem_avail_bytes{mountpoint="/exports"} / node_filesystem_size_bytes{mountpoint="/exports"}', 'free %')],
          12, 0, 12, 8, unit="percent"),
    panel("NFS server network (bytes/s)", "timeseries",
          [('rate(node_network_receive_bytes_total{instance="nfs:9100"}[1m])', 'rx'),
           ('rate(node_network_transmit_bytes_total{instance="nfs:9100"}[1m])', 'tx')], 0, 8, 12, 8, unit="Bps"),
    panel("NFS server disk IO (bytes/s)", "timeseries",
          [('rate(node_disk_read_bytes_total{instance="nfs:9100"}[1m])', 'read'),
           ('rate(node_disk_written_bytes_total{instance="nfs:9100"}[1m])', 'write')], 12, 8, 12, 8, unit="Bps"),
])

OUT.mkdir(parents=True, exist_ok=True)
for name, dash in (("cluster", cluster), ("gpu_node", gpu), ("storage", storage)):
    (OUT / f"{name}.json").write_text(json.dumps(dash, indent=2))
    print("wrote", OUT / f"{name}.json")
