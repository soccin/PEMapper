#
# Shared JVM settings for bin/picard.local and bin/picardV2. Sourced, not
# executed. Both wrappers ran a hardcoded -Xmx23g that had no connection to
# the VMEM its QRUN call site asked for, so the two could drift apart
# silently; deriving the heap from the allocation is what keeps them tied.
#

#
# Slurm exports SLURM_MEM_PER_NODE (in MB) whenever the job was submitted
# with --mem, which is every QRUN call site. Under CR_CPU_MEMORY that number
# is a hard cgroup cap, so the heap has to sit below it by enough to cover
# what the JVM allocates outside the heap -- metaspace, thread stacks,
# direct buffers, GC bookkeeping -- and the page cache picard's own writes
# push into the same cgroup.
#
# The margin is fixed rather than proportional so the historical VMEM 32 /
# -Xmx23g pairing comes back out exactly: 32768 - 9216 = 23552. Unset, as
# when a wrapper is run by hand or from doRNAQC.sh, falls back to that same
# 23g. Java's own cgroup awareness is no substitute: left to itself it takes
# 25% of the cap, which is far too little here.
#
PEMAP_XMX_MB=23552
PEMAP_JVM_HEADROOM_MB=${PEMAP_JVM_HEADROOM_MB:-9216}

if [ -n "$SLURM_MEM_PER_NODE" ]; then
    PEMAP_XMX_MB=$(( SLURM_MEM_PER_NODE - PEMAP_JVM_HEADROOM_MB ))
fi

if [ "$PEMAP_XMX_MB" -lt 2048 ]; then
    echo "FATAL ERROR: derived picard heap [${PEMAP_XMX_MB}m] is too small"
    echo "SLURM_MEM_PER_NODE=[$SLURM_MEM_PER_NODE] headroom=[${PEMAP_JVM_HEADROOM_MB}m]"
    echo "Raise the VMEM on the QRUN call site, or lower PEMAP_JVM_HEADROOM_MB."
    exit 1
fi

#
# A hard ceiling on GC threads, not a tuning knob. Java 23 does read the
# cgroup CPU limit on IRIS and picks ParallelGCThreads=2 on a -c 2
# allocation by itself, but this cap does not depend on it: several picard
# JVMs landing on one node with their GCs sized to the node's physical core
# count will bury that node. Every QRUN call site that runs picard asks for
# -c 2.
#
PEMAP_JVM_GC_OPTS="-XX:ParallelGCThreads=2 -XX:ConcGCThreads=2"
