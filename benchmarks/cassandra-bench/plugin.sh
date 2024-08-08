#
# YCSB-Cassandra benchmark plugin
#

NAME_plugin=_plugin
TIMEOUT_plugin=0
WORKLOADS_plugin="a b c d e f"
WORKLOADS_TARGETS_plugin_old="\
a//target=10000 a//target=60000  a//target=100000 a//target=160000 \
b//target=20000 b//target=80000  b//target=160000 b//target=240000 \
c//target=30000 c//target=130000 c//target=250000 c//target=320000 \
d//target=20000 d//target=90000  d//target=160000 d//target=240000 \
e//target=1200  e//target=5400   e//target=9600   e//target=14400  \
f//target=9000  f//target=40000  f//target=72000  f//target=110000 "
WORKLOADS_TARGETS_plugin="\
a//target=10000 a//target=60000  a//target=100000 \
b//target=20000 b//target=80000  b//target=160000 \
c//target=30000 c//target=130000 c//target=250000 \
d//target=20000 d//target=90000  d//target=160000 \
e//target=1200  e//target=5400   e//target=9600   \
f//target=9000  f//target=40000  f//target=72000  "

JAVA_OPTS_ZING_plugin="-ea \
-XX:+UseThreadPriorities \
-XX:ThreadPriorityPolicy=42 \
-XX:+HeapDumpOnOutOfMemoryError \
-Xss256k \
-XX:StringTableSize=1000003 \
-Djava.net.preferIPv4Stack=true \
"

JAVA_OPTS_ORACLE_plugin="-ea \
-XX:+UseThreadPriorities \
-XX:ThreadPriorityPolicy=42 \
-XX:+HeapDumpOnOutOfMemoryError \
-Xss256k \
-XX:StringTableSize=1000003 \
-XX:+AlwaysPreTouch \
-XX:-UseBiasedLocking \
-XX:+UseTLAB \
-XX:+ResizeTLAB \
-XX:+PerfDisableSharedMem \
-Djava.net.preferIPv4Stack=true \
"

SLA_CONFIG="[[50, 5, 10000], [99, 10, 10000], [99, 20, 10000], [99.9, 20, 60000], [99.9, 50, 60000], [99.99, 200, 300000], [100, 1000, 300000]]"

function env-init_plugin {
    BENCHMARK_DIR=${BASE}/benchmarks/cassandra-bench
    VM_ARGS=
    WORKLOAD_PARAMETERS=
    CLUSTER=false
    NODES=
    SCALE=
    RESTART_VM=
    YCSB_JVM_HOME=
    YCSB_JVM_OPTS=
    APP_NAME=cassandra-3.11.4
    YCSB_HOME=ycsb-0.14.0
    DATA_DIR="/localhome/$(whoami)/data_cassandra-bench"
    APPS_DIR="/localhome/$(whoami)/apps_cassandra-bench"
    SCORE_LATENCY=
    USE_HDR_plugin=
    USE_TOP_plugin=
    USE_MPSTAT_plugin=
    USE_NODETOOL_plugin=false
    NUMACTL_ARGS_YCSB_plugin=
    NUMACTL_ARGS_plugin=
    YCSB_TYPE_plugin=zing
    YCSB_HEAP_plugin=16
    CLIENT_TLS=false
}

function config_plugin {
    local alias=$1
    local warmup=
    case $alias in
#        heap[0-9]*)
#            local heap_size=${alias/heap/}
#            PMEM_PARTITIONS_DIR=$RES_DIR/pmem-partitions
#            rm -fr "${PMEM_PARTITIONS_DIR}"
#            [[ "${YCSB_TYPE_plugin}" == zing ]] && config_generic zmd-mem0-${YCSB_HEAP_plugin}G
#            [[ "$VM_TYPE" == zing* ]] && config_generic zmd-mem1-${heap_size}G
#            config_generic heap${heap_size}
#            ;;
        ramdata)
            DATA_DIR="/dev/shm/data_cassandra-bench"
            ;;
        ssddata)
            DATA_DIR="/localhome/$(whoami)/data_cassandra-bench"
            ;;
        appsdir=)
            APPS_DIR=${alias/appsdir=/}/apps_cassandra-bench
            ;;
        profile-reset)
            VM_ARGS+=" __RESET__"
            ;;
        cluster)
            CLUSTER=true
            ;;
        nodes_*)
            NODES="${alias/nodes_/}"
            ;;
        nightly)
            if [[ "$VM_TYPE" == zing* ]]
            then
                VM_ARGS="${JAVA_OPTS_ZING_plugin} ${VM_ARGS}"
                process_config heap48
                process_config logcomp
            else
                VM_ARGS="${JAVA_OPTS_ORACLE_plugin} ${VM_ARGS}"
                process_config heap48
            fi
            process_config loggc_details
            process_config nightly_nostashing
            process_config ramdata
            process_config version3.11.4
            process_config ycsb_version0.14.0
            process_config latency_report
            ;;
        weekly)
            process_config nightly
            ;;
        release)
            process_config nightly
            ;;
        oracle)
            #process_config zmd-stop
            ;;
        logcomp)
            VM_ARGS+=" __LOGCOMP__"
            ;;
        loggc_details)
            VM_ARGS+=" __LOGGC__"
            ;;
        score_latency)
            SCORE_LATENCY=true
            ;;
        hdr)
            USE_HDR_plugin=true
            ;;
        mpstat)
            USE_MPSTAT_plugin=true
            ;;
        nodetool)
            USE_NODETOOL_plugin=true
            ;;
        process_hdr)
            PROCESS_HDR_plugin=true
            ;;
        nonsaturated48)
            process_config ycsb_thr60
            process_config heap48
            process_config version3.2.1
            process_config ycsb_version0.7.0
            ;;
        nonsaturated24)
            process_config ycsb_thr30
            process_config heap24
            process_config version3.2.1
            process_config ycsb_version0.7.0
            ;;
        ycsb-mem-interleave)
            # Interleave memory across all nodes. Example: numa-mem-interleave
            NUMACTL_ARGS_YCSB_plugin+=" --interleave=all"
            ;;
        ycsb-mem[0-9,]*)
            # Only allocate memory from nodes. Example: numa-mem1
            NUMACTL_ARGS_YCSB_plugin+=" --membind=${alias/ycsb-mem/}"
            ;;
        ycsb-node[0-9,]*)
            # Only execute command on the CPUs of nodes. Example: numa-node1
            NUMACTL_ARGS_YCSB_plugin+=" --cpunodebind=${alias/ycsb-node/}"
            ;;
        cassandra-*)
            APP_NAME=${alias}
            ;;
        version*)
            APP_NAME=cassandra-${alias/version/}
            ;;
        ycsb_version*)
            YCSB_HOME=ycsb-${alias/ycsb_version/}
            ;;
        compression)
            COMPRESSION=true
            ;;
        no-compression)
            COMPRESSION=false
            ;;
        restart-vm)
            RESTART_VM=true
            ;;
        no-restart-vm)
            RESTART_VM=false
            ;;
        ycsb-zing)
            YCSB_JVM_HOME=zing-jdk1.8.0-19.01.0.0-6
            YCSB_TYPE_plugin=zing
            ;;
        ycsb-zing-old)
            YCSB_JVM_HOME=zing-jdk1.7.0-5.10.0.0-18
            YCSB_TYPE_plugin=zing
            ;;
        ycsb-tall)
            YCSB_JVM_HOME=zing-jdk1.8.0-19.01.0.0-6
            YCSB_JVM_OPTS+=" -XX:-UseZST"
            YCSB_TYPE_plugin=tall
            ;;
        ycsb-hotspot)
            YCSB_JVM_HOME=jdk-8u202-linux-x64
            YCSB_TYPE_plugin=hotspot
            ;;
        ycsb-jvm=*)
            YCSB_JVM_HOME=${alias/ycsb-jvm=/}
            ;;
        ycsb-same)
            YCSB_JVM_HOME=${JAVA_HOME}
            ;;
        ycsb-heap[0-9]*)
            YCSB_HEAP_plugin=${alias/*heap/}
            YCSB_JVM_OPTS+=" -Xms${alias/*heap/}g -Xmx${alias/*heap/}g"
            ;;
        ycsb-opts=)
            YCSB_JVM_OPTS+=" ${alias/ycsb-opts=/}"
            ;;
        ycsb_thr[0-9]*) # Number of ycsb client threads
            [[ -n "${WORKLOAD_PARAMETERS}" ]] && WORKLOAD_PARAMETERS+=,
            WORKLOAD_PARAMETERS+="threads=${alias/ycsb_thr/}"
            ;;
        ycsb_conn[0-9]*) # Number of ycsb connections
            [[ -n "${WORKLOAD_PARAMETERS}" ]] && WORKLOAD_PARAMETERS+=,
            WORKLOAD_PARAMETERS+="connections=${alias/ycsb_conn/}"
            ;;
        ycsb_time[0-9]*) # Duration of measurement
            [[ -n "${WORKLOAD_PARAMETERS}" ]] && WORKLOAD_PARAMETERS+=,
            WORKLOAD_PARAMETERS+="time=${alias/ycsb_time/}"
            ;;
        target_load[0-9]*) # Target throughput
            [[ -n "${WORKLOAD_PARAMETERS}" ]] && WORKLOAD_PARAMETERS+=,
            WORKLOAD_PARAMETERS+="target=${alias/target_load/}"
            ;;
        custom-script=*)
            CUSTOM_SCRIPT=${alias/custom-script=/}
            ;;
        latency_report)
            SCORE_LATENCY=true
            ;;
        ssl)
            CLIENT_TLS=true
            YCSB_HOME=ycsb-0.18.0
            ;;
        cluster_4nodes)
            NODES=xeongold01-10g,xeongold02-10g,xeongold03-10g,xeongold04-10g
            ;;
        *) return 1 ;;  # Indicate that alias is not handled
    esac
}

function list-workloads_plugin {
    echo $WORKLOADS_TARGETS_plugin | tr ' ' '\n' | sed 's|^|\t|g'
}

function generate_plugin {
    echo "Unpacking benchmark..."
    RES_DIR=$1
    local vm_args=${VM_ARGS}
#    [[ "$VM_TYPE" = zing-* && "$NUMACTL_ARGS" != *interleave* ]] && vm_args="-XX:AzMemPartition=1 ${vm_args}"
    (( JDK_VERSION >= 9 )) && vm_args=${vm_args/-XX:ThreadPriorityPolicy=42/}
    echo "Generating 'run.sh' in results dir: $results_dir ..."
    cat $BENCHMARK_DIR/run_template | sed "
        s|ZMD_STOP_VALUE|${ZMD_STOP}|g;
        s|ZMD_RESTART_VALUE|${ZMD_RESTART}|g;
        s|RESULTS_DIR_VALUE|${RES_DIR}|g;
        s|JAVA_HOME_VALUE|${JAVA_HOME}|g;
        s|JAVA_OPTS_VALUE|${vm_args}|g;
        s|JAVA_VERSION_VALUE|${JDK_VERSION}|g;
        s|BENCHMARK_DIR_VALUE|${BENCHMARK_DIR}|g;
        s|WORKLOAD_VALUE|${WORKLOAD_NAME}|g;
        s|WORKLOAD_ARGS_VALUE|${WORKLOAD_PARAMETERS}|g;
        s|DATA_DIR_VALUE|${DATA_DIR}|g;
        s|APPS_DIR_VALUE|${APPS_DIR}|g;
        s|CLUSTER_VALUE|${CLUSTER}|g;
        s|NODES_VALUE|${NODES}|g;
        s|COMPRESSION_VALUE|${COMPRESSION}|g;
        s|RESTART_VM_VALUE|${RESTART_VM}|g;
        s|YCSB_HOME_VALUE|${YCSB_HOME}|g;
        s|YCSB_JVM_HOME_VALUE|${YCSB_JVM_HOME}|g;
        s|YCSB_JVM_OPTS_VALUE|${YCSB_JVM_OPTS}|g;
        s|APP_NAME_VALUE|${APP_NAME}|g;
        s|USE_NODETOOL_VALUE|${USE_NODETOOL_plugin}|g;
        s|USE_HDR_VALUE|${USE_HDR_plugin}|g;
        s|USE_TOP_VALUE|${USE_TOP_plugin}|g;
        s|USE_MPSTAT_VALUE|${USE_MPSTAT_plugin}|g;
        s|NUMACTL_YCSB_VALUE|${NUMACTL_ARGS_YCSB_plugin}|g;
        s|NUMACTL_ARGS_VALUE|${NUMACTL_ARGS_plugin}|g;
        s|CUSTOM_SCRIPT_VALUE|${CUSTOM_SCRIPT}|g;
        s|SCORE_LATENCY_VALUE|${SCORE_LATENCY}|g;
        s|CLIENT_TLS_VALUE|${CLIENT_TLS}|g;
        s|SLA_CONFIG_VALUE|${SLA_CONFIG}|g;
        " > "$RES_DIR/run.sh" || exit 1
}

function find-logs_plugin {
    echo find-logs_plugin
    local newer_than_file="$1"
    LOGS=$(find $RES_DIR -type f -name scores.txt $newer_than_file)
    return 0
}

function extract-score-line_plugin {
    echo "extract-score-line_plugin $1" >> "$RES_DIR/plugin_.log"
    cat "$1" >> "$RES_DIR/plugin_.log"
    echo --- >> "$RES_DIR/plugin_.log"
    SCORE_LINE=`cat "$1" | grep "Score on"`
}

function annotate-score-line_plugin {
    local SCORE_LINE="$1"
    if [[ $SCORE_LINE =~ msgs/s ]]; then
        ANNOTATION='_throughput:asis'
    fi
    if [[ $SCORE_LINE =~ READ_AverageLatency || $SCORE_LINE =~ UPDATE_AverageLatency || $SCORE_LINE =~ percentile ]]; then
        ANNOTATION='_latency:asis'
    elif [[ "$SCORE_LINE" =~ ^Metric_file ]]; then
         ANNOTATION=':skip'
    elif [[ "$SCORE_LINE" =~ ^Metric ]]; then
         METRIC_NAME=$(echo "$SCORE_LINE" | sed 's|Metric \(.*\) on.*|\1|')
         ANNOTATION="_metric_${METRIC_NAME}:asis"
    else
        ANNOTATION=':asis'          # simple score -- put it 'as is' to the log without postfix
    fi
    echo "[$ANNOTATION] $SCORE_LINE"
}
