#!/bin/bash
# The write fails with ENOSPC; df shows 100% used. Fix: free space (here the
# stand-in tmpfs is already unmounted by the induce script).
echo "symptom: dd ... : No space left on device"
echo "fix: delete old checkpoints / grow the export, then df shows free space."
