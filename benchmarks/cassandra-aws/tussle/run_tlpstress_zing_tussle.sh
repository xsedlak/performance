#!/bin/bash
unset JAVA_HOME
unset JAVA_OPTS
unset JAVA_TYPE
unset JAVA_VERSION

export JAVA_HOME=""
export DIST_DIR=/efs/dolphin/dist
export APP_NAME=cassandra-4.0.1

JJ_HOME=/efs/aanischenko

#latest dev of Mar.03.2022
Z11=${JJ_HOME}/zing-11.zvm-dev-3842.product
Z8=${JJ_HOME}/zing20.08.0.0-4-jdk8.0.265
OJDK11=${JJ_HOME}/openjdk-11.0.2
#latest zulu of Mar.03.2022
ZULU_11=${JJ_HOME}/zulu11.54.25-ca-jdk11.0.14.1-linux_x64

GRAAL_11=/home/buildmaster/sw/j2sdk/zulu11.0.9/linux/x86_64
ZULU_8=/home/buildmaster/sw/j2sdk/zulu1.8.0_282/linux/x86_64
HS11=/home/buildmaster/sw/j2sdk/11.0.9

export NUMACTL_YCSB=none
export YCSB_JAVA_HOME=${JJ_HOME}/zing20.09.0.0-3-jdk8.0.265
export YCSB_JAVA_OPTS="-Xmx8g -Xms8g __JHICCUP__"
echo "YCSB_JAVA_HOME: ${YCSB_JAVA_HOME}"

## ./run.sh JAVA_HOME=$YCSB_JAVA_HOME finish_cassandra; exit

G1="\
-XX:+UseG1GC \
-XX:G1RSetUpdatingPauseTimePercent=5 \
-XX:MaxGCPauseMillis=300 \
-XX:InitiatingHeapOccupancyPercent=70 \
-XX:ParallelGCThreads=8 -XX:ConcGCThreads=8"

CMS11="\
-XX:+UseConcMarkSweepGC \
-XX:+CMSParallelRemarkEnabled \
-XX:SurvivorRatio=8 \
-XX:MaxTenuringThreshold=1 \
-XX:CMSInitiatingOccupancyFraction=75 \
-XX:+UseCMSInitiatingOccupancyOnly \
-XX:CMSWaitDuration=10000 \
-XX:+CMSParallelInitialMarkEnabled \
-XX:+CMSEdenChunksRecordAlways \
-XX:+CMSClassUnloadingEnabled \
-XX:ParallelGCThreads=8 \
-XX:ConcGCThreads=8 \
"

CMS8="-XX:+UseParNewGC $CMS11"

SHND="\
-XX:+UnlockExperimentalVMOptions \
-XX:+UseShenandoahGC \
-XX:ConcGCThreads=8 \
-XX:ParallelGCThreads=8 \
-XX:+UseTransparentHugePages \
"

ZGC="\
-XX:+UnlockExperimentalVMOptions \
-XX:+UseZGC \
-XX:ConcGCThreads=8 \
-XX:ParallelGCThreads=8 \
-verbose:gc \
"

CNC_HOST="10.21.81.240:30362"

CNC_COCA_MERGED_OPTS="\
-XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions \
-XX:UseKlassNameBasedKID=4190000 -XX:ProfileLogOut=rnProfile.log \
-XX:+UseCNC -XX:CNCHost=${CNC_HOST} -XX:+CNCAbortOnBadChannel -XX:-CNCLocalFallback \
-Xlog:concomp=info:file=connected-compiler-client.log -XX:+CNCInsecure \
-Xlog:persistentprofile -XX:+PrintPrecompilationStats -XX:+PrintDeoptimizationStatistics \
-XX:CNCDebugOptions=+codecache.read,+codecache.write,+codecache.merge.candidates \
"
CNC_COCA_OPTS="\
-XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions \
-XX:UseKlassNameBasedKID=4190000 -XX:ProfileLogOut=rnProfile.log \
-XX:+UseCNC  -XX:CNCHost=${CNC_HOST} -XX:+CNCAbortOnBadChannel \
-XX:-CNCLocalFallback \
-Xlog:concomp=info:file=connected-compiler-client.log -XX:+CNCInsecure \
-XX:CNCDebugOptions=+codecache.read,+codecache.write \
"

CNC_OPTS="\
-XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions \
-XX:UseKlassNameBasedKID=4190000 -XX:ProfileLogOut=rnProfile.log \
-XX:+UseCNC  -XX:CNCHost=${CNC_HOST} -XX:+CNCAbortOnBadChannel \
-XX:-CNCLocalFallback \
-Xlog:concomp=info:file=connected-compiler-client.log -XX:+CNCInsecure \
-XX:CNCDebugOptions=-codecache.read,-codecache.write \
"

UNLOCK_XX="\
-XX:+UnlockExperimentalVMOptions -XX:+UnlockDiagnosticVMOptions \
"
ZING_VM_LOG="\
-XX:+PrintCompilation -XX:+TraceDeoptimization -XX:+PrintCompilationStats -XX:+FalconDumpCompileTimes \
-XX:+LogVMOutput -XX:-DisplayVMOutput -XX:LogFile=vmoutput.log -Xlog:persistentprofile -XX:+PrintPrecompilationStats \
-XX:+PrintDeoptimizationStatistics  -XX:+PrintCompileDateStamps \
"
check_stopped() {
    if [[ -f STOP ]]
    then
        echo Detected STOP
        exit 1
    fi
}

#export NODES=xeongold02-10g,xeongold03-10g,xeongold04-10g
export NODES=node1-r5d.2xlarge,node2-r5d.2xlarge,node3-r5d.2xlarge

#export DATA_DIR="/dev/shm/data_cass"
export CASSANDRA_PROPS=num_tokens=8

#memtable_heap_space=$(( 1024*heap*50/100 ))
#echo memtable_heap_space: $memtable_heap_space
#export CASSANDRA_PROPS=num_tokens=8,memtable_heap_space_in_mb=$memtable_heap_space
export COLLECT=""

check_stopped

WL=tlp-stress
#TEST=${WL}//target=${targetRate},threads=${threads},time=${runTime},rtw=${warmupTime}
TEST=${WL}//target=${TARGET_RATE},threads=${TESTRUNNER_THREADS},time=${RUN_TIME},rtw=${WARMUP_TIME}

suff=${TEST//=/}
suff=${suff// /}
suff=${suff//\'/}
suff=${suff//,/_}
suff=${suff#*//}
suff=${suff}_ver${APP_NAME/*cassandra-/}
echo suff: ${suff}

export JAVA_HOME=$Z11
export JAVA_VERSION=11
export CONFIG_DEF=""

#
# ZING ZING ZING ZING ZING 
#
METH=()
while read OOO
do
[[ -z "${OOO}" ||  "${OOO}" == "#"* ]] && continue
echo ----- $OOO -----
METH+=( "$OOO" )
done < mopts
echo M: "${METH[@]}"

for ZING_OPTS in ""
#for ZING_OPTS in "$CC_OPTS"
#for ZING_OPTS in "-XX:+UseFalcon"
#for ZING_OPTS in "${METH[@]}"
do
pp=${ZING_OPTS}
[[ "$pp" == "$CC_OPTS" ]] && pp=kcc
pp=$( echo $pp | sed "s|-XX:+UnlockExperimentalVMOptions||g; s|-XX:||g; s|::|_|g; s|:|_|g; s|,|_|g; s|=||g; s|*|STAR|g; s|CompileCommand|CC|g; s|__|_|g; " )
pp=$( echo $pp | sed "s| |_|g;")
echo "ZING_OPTS: $ZING_OPTS"
echo "pp: $pp"
export CONFIG_DEF="${pp}"
[[ -n "$pp" ]] && pp="${pp}_"
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zing${JAVA_VERSION}_${pp}h${heap}_${suff}
./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g ${UNLOCK_XX} ${ZING_VM_LOG} __LOGGC__ __LOGCOMP__ ${ZING_OPTS}"  ${TEST}
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g ${UNLOCK_XX} ${ZING_VM_LOG} ${CNC_COCA_MERGED_OPTS} __LOGGC__ __LOGCOMP__ ${ZING_OPTS}"  ${TEST}

check_stopped
done

echo DONE
