# Benchmarks

Every number here comes from a script in this directory. The CSVs under
`results/` are a sample run on the development laptop (a Quadro P2000 machine,
Docker on WSL2); regenerate them with `make bench`.

## IO: `io/run.sh` -> `results/fio.csv`

fio, run from c1, comparing `/shared` (NFS) against `/local` (a node-local ext4
volume). Sequential 1 MiB (1 and 4 jobs), random 4 KiB at queue depth 16, direct
IO, several trials. Columns: `fs,test,jobs,trial,metric,value,lat_ms_p50,lat_ms_p99`;
`value` is MB/s for the sequential tests and IOPS for the random test.

What the sample shows: sequential write to NFS is several times slower than to
the local volume (one network file server versus a local disk). The read numbers
are inflated by caching: a file read straight after it was written is served from
the NFS server's page cache, so the read row measures cache, not disk. A cold
read needs the caches dropped on both the client and the server, which a
privileged container on WSL2 cannot always do; this is noted rather than worked
around.

## Small files: `io/smallfiles.sh` -> `results/smallfiles.csv`

The experiment that matters for AI datasets on shared storage. It stores the same
bytes two ways and reads them back: as many 4 KiB files (an unpacked image
folder) and as a few tar shards (what a data loader should stream). Run from c1
against `/shared` and `/local`. Columns: `fs,mode,metric,trial,value`.

What the sample shows, on `/shared` (NFS):

- creating files: about 50 per second, because every file is a separate metadata
  round trip to the server; the local volume does ten times more
- reading the loose files: a few MB/s; reading the same bytes as shards: about
  ten times faster

The headline is the ratio: on a shared file system, packing a dataset into a few
large shards turns tens of thousands of slow metadata operations into a handful
of streaming reads. This is why `webdataset`, `tar` shards and record files exist.

Set the size for real numbers, for example:

```
make bench SIZE=2g NFILES=200000 TRIALS=3
```

IOR and mdtest (built from source) and the data-loader comparison under Apptainer
are added with the container work.
