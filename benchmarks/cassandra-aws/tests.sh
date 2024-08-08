#!/bin/bash

unset JAVA_HOME
unset JAVA_OPTS
unset JAVA_TYPE
unset JAVA_VERSION

export JAVA_HOME=""
export DIST_DIR=/home/rscherba/dist
#export DIST_DIR=/efs/dolphin/dist
export APP_NAME=cassandra-3.11.8
export APP_NAME=cassandra-3.11.10
export APP_NAME=cassandra-4.0.1

JJ_HOME=/home/buildmaster/sw
JJ_HOME=/efs/rscherba
JJ_HOME=/home/rscherba/ws

ZULU=${JJ_HOME}/zulu1.8.0_262

Z11=${JJ_HOME}/zing21.10.0.0-3-jdk11.0.13
Z11=/home/buildmaster/nightly/ZVM/21.10/in_progress/zvm-21.10.0.0-3/sandbox/azlinux/jdk11/x86_64/product

Z8=${JJ_HOME}/zing20.08.0.0-4-jdk8.0.265

OJDK11=${JJ_HOME}/openjdk-11.0.2
OJDK11_SH=${JJ_HOME}/openjdk-shenandoah-jdk11-02-20
ZULU_11=/home/buildmaster/sw/j2sdk/zulu11.0.9/linux/x86_64
ZULU_11=${JJ_HOME}/zulu11.52.13-ca-jdk11.0.13
GRAAL_11=/home/buildmaster/sw/j2sdk/zulu11.0.9/linux/x86_64
ZULU_8=/home/buildmaster/sw/j2sdk/zulu1.8.0_282/linux/x86_64

HS11=/home/buildmaster/sw/j2sdk/11.0.9

export NUMACTL_YCSB=none
#export YCSB_JAVA_HOME=/home/rscherba/ws/zing20.08.0.0-4-jdk8.0.265-linux_x64
#export YCSB_JAVA_HOME=/home/rscherba/ws/jdk1.8.0_202
export YCSB_JAVA_OPTS="-Xmx16g -Xms16g __JHICCUP__"
#export YCSB_JAVA_OPTS="-Xmx8g -Xms8g __JHICCUP__ -XX:-UseZST"
#export YCSB_JAVA_HOME=/home/rscherba/ws/jdk_latest
#export YCSB_JAVA_OPTS="-Xmx8g -Xms8g __JHICCUP__"
export YCSB_JAVA_HOME=/home/buildmaster/sw/j2sdk/zulu11.0.9/linux/x86_64 # important! NoSQLBench jar requires newer versions
export YCSB_JAVA_HOME=/home/rscherba/ws/zing20.08.0.0-4-jdk8.0.265 # important! tlp-stress doesn't work with other builds
#export YCSB_JAVA_HOME=${JJ_HOME}/zing20.09.0.0-3-jdk8.0.265
export YCSB_JAVA_OPTS="-Xmx16g -Xms16g __JHICCUP__"
export YCSB_JAVA_OPTS="-Xmx8g -Xms8g __JHICCUP__"

#export TLP_STRESS_HOME=/home/rscherba/ws/cassandra/tlp-stress-4.0.0m5

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

CC_HOST="10.21.20.166:30754"

CC_OPTS="\
-XX:+CCAbortOnBadChannel \
-XX:+UnlockExperimentalVMOptions \
-Xlog:concomp=info:file=cc-client.log \
-XX:CCSSLRootsPath=/efs/rscherba/cert.pem \
-XX:CCSSLTargetNameOverride=test.azul.com -XX:-CCInsecure \
-XX:CCHost=${CC_HOST} \
"

# -XX:+UseTransparentHugePages
# +UseTransparentHugePages on a tmpfs filesystem not supported by kernel

JFR_ZING="\
-XX:StartFlightRecording=dumponexit=true,maxsize=10G \
-XX:+UseTickProfilerAsJFRThreadSampler \
-XX:TickProfilerFrequency=10000 \
-XX:SlowTickProfilerFrequency=10000 \
"

JFR="\
-XX:+UnlockCommercialFeatures \
-XX:+FlightRecorder \
-XX:StartFlightRecording=delay=20s,duration=60s,name=myrecording,filename=profile.jfr,settings=profile
"

ZVR="-XX:ARTAPort=9999 -XX:+UseTickProfiler"
SPEC_OPTS1="-XX:+UnlockExperimentalVMOptions -XX:-FalconSpeculateUncountedLoops -XX:-FalconSpeculateUnreachedCalls -XX:-FalconSpeculateUnreachedJumps -XX:-FalconSpeculateUnreachedSwitchCases"
SPEC_OPTS2="-XX:+UseEarlyClassLoading -XX:DynamicBranchEliminationLevel=0 -XX:-FalconSpeculateUnreachedJumps -XX:-FalconSpeculateUnreachedCalls"

check_stopped() {
    if [[ -f STOP ]]
    then
        echo Detected STOP
        exit 1
    fi
}

copy_profiles() {
    local res_from=$1
    local res_to=$2
    find "${res_from}" -name "node_*" | while read p
    do
        if [[ -f "${p}/profile-out" ]]
        then
            local node=${p##*\/}
            mkdir -p "${res_to}/${node}"
            cp -v "${p}/profile-out" "${res_to}/${node}/profile-in"
        fi
    done
}

for threads in  8
do

for t in  60m
do

for heap in 40
do

for target in 90k 80k
#for target in 20k 30k 40k 50k 60k 70k 80k 90k 100k 105k 110k 120k 130k
do

for dat in 1
do

export NODES=r3.2xlarge.1,r3.2xlarge.2,r3.2xlarge.3
export NODES=r5dn.2xlarge.1,r5dn.2xlarge.2,r5dn.2xlarge.3
export NODES=r5d.2xlarge.1
export NODES=$(hostname)
export NODES=xeongold02-10g
export NODES=r5.12xlarge
export NODES=xeongold02-10g,xeongold03-10g
export NODES=xeongold02-10g,xeongold03-10g,xeongold04-10g
export NODES=xeongold03-10g,xeongold04-10g
export NODES=xeongold03,xeongold04
export NODES=xeongold02,xeongold03,xeongold04
export NODES=perfs
export NODES=r5d.2xlarge.1,r5d.2xlarge.2,r5d.2xlarge.3
export NODES=xeongold01-10g
export NODES=xeongold02-10g,xeongold03-10g,xeongold04-10g

export NODES=node1-i3en.2xlarge,node2-i3en.2xlarge,node3-i3en.2xlarge

#export DATA_DIR="/dev/shm/data_cass"

#export DOCKER=true
#export DOCKER_CPUS=8
#export NODE_CPU=true
#export DOCKER_MEM=64

export CASSANDRA_PROPS=num_tokens=8,memtable_heap_space_in_mb=3072,memtable_offheap_space_in_mb=3072
export CASSANDRA_PROPS=num_tokens=8,memtable_heap_space_in_mb=30720,memtable_offheap_space_in_mb=30720
export CASSANDRA_PROPS=num_tokens=8,write_request_timeout_in_ms=20000,read_request_timeout_in_ms=20000
export CASSANDRA_PROPS=num_tokens=8,read_request_timeout_in_ms=20000,write_request_timeout_in_ms=20000,counter_write_request_timeout_in_ms=20000,request_timeout_in_ms=20000,cas_contention_timeout_in_ms=10000
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch=false
export CASSANDRA_PROPS=""
export CASSANDRA_PROPS=num_tokens=8,endpoint_snitch=GossipingPropertyFileSnitch
export CASSANDRA_PROPS=dynamic_snitch_reset_interval_in_ms=60000
export CASSANDRA_PROPS=dynamic_snitch=false
export CASSANDRA_PROPS=dynamic_snitch_reset_interval_in_ms=30000
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms=900000
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms@1=60000
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms@2=60000
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms@3=60000
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms@1=120000
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms=60000
memtable_heap_space=$(( heap*80/100 ))
echo memtable_heap_space: $memtable_heap_space
export CASSANDRA_PROPS=num_tokens=8,memtable_heap_space_in_mb=$memtable_heap_space
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms=70000,dynamic_snitch_badness_threshold=5.0
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms=70000,dynamic_snitch_update_interval_in_ms=300
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms=70000,read_request_timeout_in_ms=20055,write_request_timeout_in_ms=20011,counter_write_request_timeout_in_ms=20022,request_timeout_in_ms=20033,cas_contention_timeout_in_ms=20044,range_request_timeout_in_ms=20066
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms=70000,dynamic_snitch=false
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch=false
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms=7000
export CASSANDRA_PROPS=num_tokens=8,dynamic_snitch_reset_interval_in_ms=70000
export CASSANDRA_PROPS=num_tokens=256,max_hints_delivery_threads=8,key_cache_size_in_mb=1024,commitlog_segment_size_in_mb=256,concurrent_reads=16,concurrent_writes=64,concurrent_counter_writes=16,trickle_fsync=true,read_request_timeout_in_ms=10000,write_request_timeout_in_ms=10000,counter_write_request_timeout_in_ms=10000
export CASSANDRA_PROPS=num_tokens=256,max_hints_delivery_threads=8,key_cache_size_in_mb=1024,commitlog_segment_size_in_mb=256,concurrent_reads=16,concurrent_writes=64,concurrent_counter_writes=16,trickle_fsync=true,read_request_timeout_in_ms=20000,write_request_timeout_in_ms=20000,counter_write_request_timeout_in_ms=20000
export CASSANDRA_PROPS=num_tokens=8

export COLLECT="/home/buildmaster/sw/developerstudio/12.6/bin/collect -d . -j off -p hi"
export COLLECT="/home/buildmaster/sw/developerstudio/12.6/bin/collect -d . -j off"
export COLLECT="/home/buildmaster/sw/developerstudio/12.6/bin/collect -d ."
export COLLECT=""

#export RUN_PAR_JOB=deopt,850,500
#export RUN_PAR_JOB=deopt,60,50

check_stopped

WL=nb
TEST=${WL}//threads=10,cycles=50000
TEST=${WL}//threads=10
TEST=${WL}//d=${dat}

WL=tlp-stress
TEST=${WL}//target=${target},time=${t},rr=0.8
TEST=${WL}//target=${target},threads=${threads},time=${t},replication=0
TEST=${WL}//target=${target},threads=${threads},time=${t}

#WL=cassandra-tus
#TEST=${WL}//time=30,ratePercentStep=10
#TEST=${WL}//time=300,ratePercentStep=10,rangeStartTime=30

#TEST=init_and_start_cassandra
#TEST=finish_cassandra

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
#export CONFIG_DEF="${pp} xmx-only"
#export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zing${JAVA_VERSION}${pp}xmx${heap}_${suff}
#./run.sh  JAVA_OPTS="-Xmx${heap}g __LOGGC__ __LOGCOMP__ ${ZING_OPTS}"  ${TEST}
#check_stopped
export CONFIG_DEF="${pp}"
[[ -n "$pp" ]] && pp="${pp}_"
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zing${JAVA_VERSION}_${pp}h${heap}_${suff}
./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g __LOGGC__ __LOGCOMP__ ${ZING_OPTS}"  ${TEST}
check_stopped
done

#
# RN RN RN RN RN
#
if false
then

ZING_OPTS="-XX:-UseFalcon -XX:+UseKestrelC2"
ZING_OPTS=""
ZING_OPTS="-XX:-UseFalcon -XX:+UseSeaOfNodesC2"
ZING_OPTS="-XX:+UseKestrelC2"
pp=$( echo ${ZING_OPTS} | sed "s|-XX:+UnlockExperimentalVMOptions||g; s|-XX:||g; s| |_|g;" )
pp=$( echo $pp )
echo "RN-pp: $pp"

#PROF_OPS="-XX:-FalconUseCompileStashing -XX:+UnlockExperimentalVMOptions -XX:+ProfileForcePreinitializeEnums -XX:+ProfileForcePreinitializeBootstrapClasses -XX:+ProfileForcePreinitializeClasses"
PROF_OPS="-XX:-FalconUseCompileStashing __LOGGC__ __LOGCOMP__ ${ZING_OPTS}"

STAMP1=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zing${JAVA_VERSION}_${pp}_h${heap}_RN-1_${suff}
export STAMP=${STAMP1}
export CONFIG_DEF="out1"
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g -XX:ProfileLogOut=profile-out ${PROF_OPS}"  $TEST
check_stopped

STAMP2=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zing${JAVA_VERSION}_${pp}_h${heap}_RN-2_${suff}
export STAMP=${STAMP2}
#copy_profiles results_${STAMP1} results_${STAMP2}
export CONFIG_DEF="out2"
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g -XX:ProfileLogOut=profile-out -XX:ProfileLogIn=profile-in ${PROF_OPS}"  $TEST
check_stopped

STAMP3=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zing${JAVA_VERSION}_${pp}_h${heap}_RN-3_${suff}
export STAMP=${STAMP3}
#copy_profiles results_${STAMP2} results_${STAMP3}
export CONFIG_DEF="out3"
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g -XX:ProfileLogOut=profile-out -XX:ProfileLogIn=profile-in ${PROF_OPS}"  $TEST
check_stopped

STAMP4=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zing${JAVA_VERSION}_${pp}_h${heap}_RN-4_${suff}
export STAMP=${STAMP4}
#copy_profiles results_${STAMP3} results_${STAMP4}
export CONFIG_DEF="out4"
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g -XX:ProfileLogOut=profile-out -XX:ProfileLogIn=profile-in ${PROF_OPS}"  $TEST
check_stopped

STAMP5=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zing${JAVA_VERSION}_${pp}_h${heap}_RN-5_${suff}
export STAMP=${STAMP5}
#copy_profiles results_${STAMP4} results_${STAMP5}
export CONFIG_DEF="out5"
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g -XX:ProfileLogOut=profile-out -XX:ProfileLogIn=profile-in ${PROF_OPS}"  $TEST
check_stopped

fi

unset JAVA_HOME
unset JAVA_VERSION
unset CONFIG_DEF
unset STAMP

#
# SHENANDOAH
#
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_ojdk11_h${heap}_shnd_${suff}
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g $SHND __LOGGC__"  JAVA_HOME=$OJDK11_SH  JAVA_VERSION=11  $TEST
check_stopped

#
# ZGC
#
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_ojdk11_h${heap}_zgc_${suff}
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g $ZGC __LOGGC__"  JAVA_HOME=$OJDK11  JAVA_VERSION=11  $TEST
check_stopped

#
# HOTSPOT
#
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_hotspot11_h${heap}_${suff}
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g __LOGGC__"  JAVA_HOME=$HS11  JAVA_VERSION=11  $TEST
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g __LOGGC__ $JFR"  JAVA_HOME=$HS11  JAVA_VERSION=11  $TEST
check_stopped

#
# OPENJDK CMS
#
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_ojdk11_h${heap}_cms_${suff}
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g $CMS11 __LOGGC__"  JAVA_HOME=$OJDK11  JAVA_VERSION=11  $TEST
check_stopped

#
# OPENJDK G1
#
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_ojdk11_h${heap}_g1_${suff}
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g $G1 __LOGGC__"  JAVA_HOME=$OJDK11  JAVA_VERSION=11  $TEST
check_stopped

#
# ZULU
#
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zulu11_h${heap}_${suff}
./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g __LOGGC__"  JAVA_HOME=$ZULU_11  JAVA_VERSION=11  $TEST
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zulu8_h${heap}_${suff}
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g __LOGGC__"  JAVA_HOME=$ZULU_8  JAVA_VERSION=8  $TEST
check_stopped

#
# ZULU CMS
#
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zulu11_h${heap}_cms_${suff}
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g $CMS11 __LOGGC__"  JAVA_HOME=$ZULU_11  JAVA_VERSION=11  $TEST
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zulu8_h${heap}_cms_${suff}
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g $CMS8 __LOGGC__"  JAVA_HOME=$ZULU_8  JAVA_VERSION=8  $TEST
check_stopped

#
# ZULU G1
#
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_zulu11_h${heap}_g1_${suff}
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g $G1 __LOGGC__"  JAVA_HOME=$ZULU_11  JAVA_VERSION=11  $TEST
check_stopped

#
# GRAAL
#
export STAMP=$(date -u '+%Y%m%d_%H%M%S')_${WL}_graal11_h${heap}_g1_${suff}
#./run.sh  JAVA_OPTS="-Xms${heap}g -Xmx${heap}g"  JAVA_HOME=$GRAAL_11  JAVA_VERSION=11  $TEST
check_stopped

done
done
done
done
done

echo DONE
