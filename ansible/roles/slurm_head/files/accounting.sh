#!/bin/bash
# Accounting bootstrap, run on the head node. Idempotent: "add" of an existing
# object is ignored, "modify" sets the values every time.
#   accounts: lab-a (alice, bob) fair share 60; lab-b (carol) fair share 40
#   QoS:      normal (4 jobs, 4 CPUs per user), high (priority 1000), debug (10 min)
set -u
S="sacctmgr -i"

$S add cluster minihpc >/dev/null 2>&1 || true

$S add account lab-a Cluster=minihpc Description="lab a" Organization=lab >/dev/null 2>&1 || true
$S add account lab-b Cluster=minihpc Description="lab b" Organization=lab >/dev/null 2>&1 || true
$S modify account lab-a set Fairshare=60 >/dev/null
$S modify account lab-b set Fairshare=40 >/dev/null

$S add qos normal >/dev/null 2>&1 || true
$S add qos high   >/dev/null 2>&1 || true
$S add qos debug  >/dev/null 2>&1 || true
$S modify qos normal set Priority=0    MaxJobsPU=4 MaxTRESPU=cpu=4 >/dev/null
$S modify qos high   set Priority=1000 >/dev/null
$S modify qos debug  set Priority=0    MaxWall=00:10:00 >/dev/null

for u in alice bob; do
    $S add user "$u" Account=lab-a DefaultAccount=lab-a >/dev/null 2>&1 || true
done
$S add user carol Account=lab-b DefaultAccount=lab-b >/dev/null 2>&1 || true

# Every account may use every QoS; normal is the default.
$S modify account lab-a set QOS=normal,high,debug DefaultQOS=normal >/dev/null
$S modify account lab-b set QOS=normal,high,debug DefaultQOS=normal >/dev/null

sacctmgr show assoc format=cluster,account,user,share,qos,defaultqos -P
sacctmgr show qos format=name,priority,maxjobspu,maxtrespu,maxwall -P
