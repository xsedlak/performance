#!/bin/bash
#
# Copyright 2018-2021 Azul Systems Inc.  All Rights Reserved.
#
# Please contact Azul Systems, 385 Moffett Park Drive, Suite 115,
# Sunnyvale, CA 94089 USA or visit www.azul.com if you need additional
# information or have any questions.
#
# Common used utility methods
#

SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd -P)

################################################
# Generic variables
#
PAR=${PAR:-0}
DATA_DIR=${DATA_DIR:-$( if [[ -d /ssd1 ]]; then echo /ssd1/$(whoami)/data_${BENCHMARK}; elif [[ -d /localhome ]]; then echo /localhome/$(whoami)/data_${BENCHMARK}; else echo $(pwd)/data_${BENCHMARK}__HOSTNAME_; fi )}
APPS_DIR=${APPS_DIR:-$( if [[ -d /ssd1 ]]; then echo /ssd1/$(whoami)/apps_${BENCHMARK}; elif [[ -d /localhome ]]; then echo /localhome/$(whoami)/apps_${BENCHMARK}; else echo $(pwd)/apps_${BENCHMARK}__HOSTNAME_; fi )}
STAMP=${STAMP:-$(date -u '+%Y%m%d_%H%M%S')}
RESULTS_DIR=${RESULTS_DIR:-"$(pwd)/results_$STAMP"}

WAIT_TIME=${WAIT_TIME:-300}
USE_JHICCUP=${USE_JHICCUP:-true}
USE_IPSTATS=${USE_IPSTATS:-true}
USE_TOP=${USE_TOP:-true}
USE_MPSTAT=${USE_MPSTAT:-true}
USE_DISKSTATS=${USE_DISKSTATS:-true}
USE_VMSTAT=${USE_VMSTAT:-true}
CLUSTER=${CLUSTER:-false}
DROP_CACHES=${DROP_CACHES:-true}
CLEAN_DEV_SHM=${CLEAN_DEV_SHM:-true}
CLUSTER_NAME=${CLUSTER_NAME:-${BENCHMARK%-*}_perf_test}

HOSTNAME_CMD=${HOSTNAME_CMD:-"hostname -A"}
HOSTNAME=$( ${HOSTNAME_CMD} )
HOSTNAME=( ${HOSTNAME} )
HOSTNAME=$(echo ${HOSTNAME})

CLIENT_JAVA_HOME=${CLIENT_JAVA_HOME:-/home/rscherba/ws/jdk_latest}
JAVA_HOME=${JAVA_HOME:-/home/rscherba/ws/jdk_latest}
JAVA_VERSION=${JAVA_VERSION:-}
JAVA_TYPE=${JAVA_TYPE:-}
#JAVA_OPTS_GC_LOG="-XX:+PrintGCDetails -XX:+PrintGCDateStamps -XX:+PrintGCApplicationStoppedTime -Xloggc:__DIR__/__NAME___%t.%p_gc.log"
JAVA_OPTS_GC_LOG="-XX:+PrintGCDetails -Xloggc:__DIR__/__NAME___%t.%p_gc.log"
JAVA_OPTS_GC_LOG11="-XX:+PrintGCDetails -Xlog:gc::utctime -XX:NativeMemoryTracking=summary -Xloggc:__DIR__/__NAME___%t.%p_gc.log"
JAVA_OPTS_COMP_LOG="-XX:+PrintCompilation -XX:+TraceDeoptimization -XX:+PrintCompilationStats -XX:+PrintCompileDateStamps -XX:-DisplayVMOutput -XX:+LogVMOutput -XX:LogFile=__DIR__/__NAME___%t.%p_comp.log"
JAVA_OPTS_CMS="-XX:+UseConcMarkSweepGC -XX:CMSInitiatingOccupancyFraction=75 -XX:+UseCMSInitiatingOccupancyOnly -XX:+AlwaysPreTouch"
JAVA_OPTS_G1="-XX:+UseG1GC"
JAVA_OPTS_FALCON="-XX:+UseFalcon"
JAVA_OPTS_C2="-XX:-UseFalcon -XX:+UseC2"
RESET_INTERVAL=${RESET_INTERVAL:-300000}
RESET_ITERATIONS=${RESET_ITERATIONS:-1000}
JHICCUP_ARGS=${JHICCUP_ARGS:-"-l,__DIR__/hiccup___NAME__.%date.%pid.hlog"}

TIME_FORMAT_Z="%Y%m%dT%H%M%SZ"
LOG_PREF=""
LOG_SEP="-------------------------------------------------------------------------------"

NODES_WITH_PORTS=""
NODES_IP=""
NODES_IP_WITH_PORTS=""
NUM_NODES=0
STOP=false
declare -A DEFAULT_PORTS
DEFAULT_PORTS[kafka]=0
DEFAULT_PORTS[cassandra]=0
DEFAULT_PORTS[elasticsearch]=9200
ARGS=()
ARGS_NUM=0

EXT_SSH_ARGS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"

jq="${SCRIPT_DIR}/jq"

################################################
# basic functions
#

is_true() {
    if [[ "${1}" == 1 || "${1}" == true || "${1}" == TRUE || "${1}" == yes || "${1}" == YES || "${1}" == on || "${1}" == ON ]]
    then
        return 0
    else
        return 1
    fi
}

sys_time() {
    date +%s
}

get_stamp() {
    local p=$(date -u "+%Y-%m-%d %H:%M:%S,%N")
    echo ${p::23},UTC
}

iso_time() {
    echo "$@" | sed "s|,.*||; s|\[||; s| |T|"
}

iso_time_test() {
    local p=$(get_stamp)
    echo "$p -> $(iso_time $p)"
}

log() {
    local p=
    echo "$(get_stamp) ${p}[${HOSTNAME}] [$$] ${LOG_PREF}${@}" >&2
}

logd() {
    [[ "$DEBUG" == true ]] && log "[DEBUG] $@"
}

log_sep() {
    log $LOG_SEP
}

fail() {
    log "FAILURE: ${@}"
    exit 1
}

logx() {
    local pref=$1
    while IFS= read -r p
    do
        [[ -n "$p" ]] && \
        log "${pref}${p}"
    done
}

log_cmd() {
    log_sep
    [[ -n "$1" ]] && log "$1"
    shift
    log "CMD: ${*}"
    set -o pipefail
    bash -c "${*}" |& logx '### '
    local res=$?
    log "exit code: $res"
    log_sep
    return $res
}

sleep_for() {
    local nj=${1:-0}
    local sj
    log "Sleeping ${nj} seconds..."
    for (( sj = 0; sj < nj; sj++ ))
    do
        sleep 1
        (( (sj+1) % 10 == 0 )) && log "slept $((sj+1))..."
    done
    log "slept total $((sj))"
}

process_args() {
    while [[ "$1" == *=* ]]
    do
        [[ "$1" == *//* ]] && break
        export "$1"
        logd "Exported: '$1'"
        shift
    done
    for var_arg in "$@"
    do
        ARGS[$ARGS_NUM]=$var_arg
        (( ARGS_NUM++ ))
        shift
    done
}

calc() {
    [[ -n "$bc" ]] || return 1
    local res=$(echo "${@}" | $bc)
    if echo $res | grep -q '\.'
    then
        echo $res | sed "s|[0]*$||;s|\.$||"
    else
        echo $res
    fi
}

check_bc() {
    if echo "1 + 2" | bc &> /dev/null
    then
        bc=bc
    else
        bc="${SCRIPT_DIR}/bc"
    fi
    local res=$(calc "1 + 2")
    if [[ "$res" != 3 ]]
    then
        unset bc
        fail "BC verification failed!"
    fi
}

mkdir_w() {
    local dir=$1
    logd "Making dir: $dir..."
    mkdir -p "${dir}" || return 1
    logd "Changing dir perms: $dir..."
    chmod uga+rw "${dir}" || return 1
    return 0
}

host_cmd() {
    local host=$1
    shift
    if [[ "${host}" == 127.0.0.1 || "${host}" == localhost ]]
    then
        log "Local command: '${@}'"
        bash -c "${@}"
    else
        log "Remote command on host ${host}: '${@}'"
        local host_ip=$(resolve_hostname "$host")
        host_ip=${host_ip:-"$host"}
        ssh ${EXT_SSH_ARGS} "${host_ip}" "source /etc/profile; ${@}"
    fi
}

remote_cmd() {
    local host=$1
    shift
    log "Remote command on host ${host}: '${@}'"
    ssh ${EXT_SSH_ARGS} "${host}" "source /etc/profile; ${@}"
}

abs_dir() {
    local path=$1
    [[ "$path" != /* ]] && path=$(readlink -f "$path")
    echo "$path"
}

real_dir() {
    local path=$1
    [[ "$path" != /* || -e "$path" ]] && path=$(readlink -f "$path")
    echo "$path"
}

make_abs_pathes() {
    [[ -n "${DIST_DIR}" ]] && DIST_DIR=$(abs_dir "${DIST_DIR}")
    [[ -n "${RESULTS_DIR}" ]] && RESULTS_DIR=$(abs_dir "${RESULTS_DIR}")
    [[ -n "${JAVA_HOME}" ]] && JAVA_HOME=$(real_dir "${JAVA_HOME}")
    [[ -n "${CLIENT_JAVA_HOME}" ]] && CLIENT_JAVA_HOME=$(real_dir "${CLIENT_JAVA_HOME}")
}

chop() {
    local p=$1
    echo ${p:0:${#p}-1}
}

get_data_dir() {
    local hname=${1:-${HOSTNAME}}
    local par
    (( PAR > 0 )) && par="_par${PAR}"
    echo "${DATA_DIR/_HOSTNAME_/${hname}}${par}"
}

get_apps_dir() {
    local hname=${1:-${HOSTNAME}}
    local par
    (( PAR > 0 )) && par="_par${PAR}"
    echo "${APPS_DIR/_HOSTNAME_/${hname}}${par}"
}

clean_dev_shm() {
    [[ "$CLEAN_DEV_SHM" == true ]] || return
    log "Cleaning /dev/shm..."
    find /dev/shm -maxdepth 1 ! -name 'queue.*' ! -path /dev/shm -print -exec rm -fr {} + |& logx "### "
}

resolve_hostname() {
    local host_name=$1
    local hosts_file=${HOSTS_FILE}
    local res
    [[ -f "${RESULTS_DIR}/hosts" ]] && hosts_file="${RESULTS_DIR}/hosts"
    if [[ -f "${hosts_file}" ]]
    then
        res=$(cat "${hosts_file}" | grep " ${host_name}$" | sed "s| ${host_name}$||")
        if [[ -n "${res}" ]]
        then
            echo ${res}
            return 0
        fi
    fi
    if res=$(host "${host_name}" | head -1)
    then
        if echo ${res} | grep -q "has address"
        then
            echo ${res} | sed "s|.* has address ||"
        elif echo ${res} | grep -q "domain name pointer"
        then
            echo ${host_name}
        fi
    else
        return 1
    fi
}

detect_hostname() {
    local ip_address=$1
    local res
    if res=$(host "$ip_address")
    then
        if echo $res | grep -q "has address"
        then
            echo $res | sed "s| has address .*||"
        elif echo $res | grep -q "domain name pointer"
        then
            chop $(echo $res | sed "s|.* domain name pointer ||")
        fi
    else
        return 1
    fi
}

sync_dirs() {
    local db1=$1
    local db2=$2
    if [[ "${db1}" != "${db2}" ]]
    then
        t1=$(date +%s)
        log "Syncing directories ${db1} to ${db2}..."
        if mkdir_w "${db2}" &&  rsync --delete -ahv "${db1}/" "${db2}"
        then
            t2=$(date +%s)
            log "Dirs rsync time: $((t2 - t1))"
            du -hs "${db2}"
        else
            log "Failed to sync dirs!"
            return 1
        fi
    else
        log "Skipped sync the same dir itself."
    fi
    return 0
}

install_artifact() {
    local name=$1
    local install_dir=$2
    local force_remove=$3
    if [[ -z "${name}" ]]
    then
        log "Missing install name!"
        return 1
    fi
    if [[ ! -d "${DIST_DIR}" ]]
    then
        log "Distributives dir (DIST_DIR) not found: ${DIST_DIR}!"
        return 1
    fi
    local archive
    [[ -e "$archive" ]] || archive=$(find "${DIST_DIR}" -name "*${name}-bin.tar.gz")
    [[ -e "$archive" ]] || archive=$(find "${DIST_DIR}" -name "*${name}.tar.gz")
    [[ -e "$archive" ]] || archive=$(find "${DIST_DIR}" -name "*${name}.tgz")
    [[ -e "$archive" ]] || archive=$(find "${DIST_DIR}" -name "*${name}-*bin.tar.gz")
    [[ -e "$archive" ]] || archive=$(find "${DIST_DIR}" -name "*${name}-*.tar.gz")
    [[ -e "$archive" ]] || archive=$(find "${DIST_DIR}" -name "*${name}-*.tgz")
    if [[ -e "$archive" ]]
    then
        local app_home="${install_dir}/${name}"
        if [[ "${force_remove}" == true ]]
        then
            log "Cleaning target dir: ${app_home}..."
            rm -fr "${app_home}" || return 1
        fi
        mkdir -p "${app_home}" || return 1
        log "Installing '$name' from tarball: $archive to dir: $install_dir"
        tar -xzf "$archive" -C "${app_home}" --strip-components=1 || return 1
#        if [[ -f $SCRIPT_DIR/patch.txt ]]
#        then
#            pushd "${app_home}"
#            patch -p1 < $SCRIPT_DIR/patch.txt || { popd; return 1; }
#            popd
#        fi
        return 0
    else
        log "Failed to install '$name'!"
        return 1
    fi
}

################################################
# 'node' helper functions
#

var_nodes=()

_IS_NUMBER='^[0-9]+$'

get_node_from_param() {
    local node=$1
    if [[ "${node}" == LAST_NODE || "${node}" =~ $_IS_NUMBER ]]
    then
        IFS=,
        local nodes=( ${NODES:-localhost} )
        unset IFS
        local node_count=${#nodes[@]}
        local idx=$((node_count - 1))
        if [[ "${node}" == LAST_NODE ]]
        then
            idx=$((node_count - 1))
        else
            idx=${node}
        fi
        node=${nodes[$idx]}
    fi
    echo -n "$node"
}

is_first_node() {
    local idx=$1
    local is_first=true
    IFS=,
    local nodes=( ${NODES:-localhost} )
    unset IFS
    local node=${nodes[$idx]}
    local node_host=${node%:*}
    for (( ii = 0; ii < idx; ii++ ))
    do
        local node0=${nodes[$ii]}
        local node0_host=${node0%:*}
        [[ "${node0_host}" == "${node_host}" ]] && is_first=false
    done
    echo -n $is_first
}

get_node_count() {
    IFS=,
    local nodes=( ${NODES:-localhost} )
    unset IFS
    echo -n ${#nodes[@]}
}

get_node_name() {
    local idx=$1
    IFS=,
    local nodes=( ${NODES:-localhost} )
    unset IFS
    local node=${nodes[$idx]}
    local node_name=${node/:/_}
    echo -n "$node_name"
}

get_node_host() {
    local idx=$1
    IFS=,
    local nodes=( ${NODES:-localhost} )
    unset IFS
    local node=${nodes[$idx]}
    local node_host=${node%:*}
    echo -n "$node_host"
}

get_master_node() {
    local resolve=$1
    local res
    if [[ -n "$var_nodes" ]]
    then
        res=${var_nodes[0]}
    else
        res=localhost
    fi
    [[ "${resolve}" == true ]] && res=$(resolve_hostname "$res")
    echo $res
}

parse_nodes() {
    if (( NUM_NODES > 0 ))
    then
        log "Parse nodes: ${NODES:-localhost} - already parsed $NUM_NODES"
        return
    fi
    log "Parse nodes: ${NODES:-localhost}..."
    local app_name=$1
    local app_name_lc=${app_name,,}
    NODES_WITH_PORTS=""
    NODES_IP=""
    NODES_IP_WITH_PORTS=""
    local res=0
    local node
    if [[ -n "$NODES" ]]
    then
        IFS=,
        var_nodes=( $NODES )
        unset IFS
        NUM_NODES="${#var_nodes[@]}"
        log "  master node: ${var_nodes[0]}"
        log "  num nodes: $NUM_NODES"
        for node in "${var_nodes[@]}"
        do
            local node_host=${node%:*}
            node_ip=$(resolve_hostname "$node_host")
            log "  node $node, IP: $node_ip"
            if [[ -n "$NODES_WITH_PORTS" ]]
            then
                NODES_WITH_PORTS="${NODES_WITH_PORTS},"
                NODES_IP="${NODES_IP},"
                NODES_IP_WITH_PORTS="${NODES_IP_WITH_PORTS},"
            fi
            local port=${DEFAULT_PORTS[$app_name_lc]}
            [[ "${node}" == *:* ]] && port=${node#*:}
            NODES_WITH_PORTS="${NODES_WITH_PORTS}${node}:${port}"
            NODES_IP="${NODES_IP}${node_ip}"
            NODES_IP_WITH_PORTS="${NODES_IP_WITH_PORTS}${node_ip}:${port}"
        done
    else
        var_nodes=( localhost )
        NUM_NODES=1
        local port=${DEFAULT_PORTS[$app_name_lc]}
        NODES_WITH_PORTS="localhost:${port}"
        NODES_IP="127.0.0.1"
        NODES_IP_WITH_PORTS="127.0.0.1:${port}"
        log "  master node: localhost"
        log "  num nodes: $NUM_NODES"
    fi
    log "Parse nodes done: $NUM_NODES -> ${var_nodes[@]}"
    return $res
}

init_nodes() {
    logd "[init_nodes] ==============================================="
    logd "[init_nodes] $@"
    local app_name=$1
    shift
    local init_node=$1
    shift
    local res=0
    local node
    parse_nodes "$app_name"
    local n=${#var_nodes[@]}
    logd "[init_nodes] $n - ${var_nodes[@]}"
    local node_num=0
    for node in "${var_nodes[@]}"
    do
        $STOP && break
        (( node_num++ ))
        logd "[init_nodes] $app_name node #$i: $init_node '$node'..."
        if ! $init_node "$node" "$node_num" "${@}"
        then
            log "[init_nodes] $app_name failed to $init_node '$node' '${@}'!"
            res=1
            break
        fi
    done
    return $res
}

start_nodes() {
    logd "[start_nodes] ==============================================="
    logd "[start_nodes] $@"
    local app_name=$1
    shift
    local start_node=$1
    shift
    local res=0
    local node
    parse_nodes "$app_name"
    local i00
    local n=${#var_nodes[@]}
    logd "[start_nodes] $n - ${var_nodes[@]}"
    local node_num=0
    for (( i00 = 0; i00 < n; i00++ ))
    do
        (( node_num++ ))
        local node=${var_nodes[i00]}
        $STOP && break
        logd "[start_nodes] $app_name node #$i00: $start_node '$node' '${@}'..."
        if ! $start_node "$node" "$node_num" "${@}"
        then
            log "[start_nodes] $app_name failed to $start_node '$node' '${@}'!"
            return 1
        fi
    done
    return 0
}

finish_nodes() {
    logd "[finish_nodes] ==============================================="
    logd "[finish_nodes] $@"
    local app_name=$1
    shift
    local finish_node=$1
    shift
    parse_nodes "$app_name"
    local i11
    local n=${#var_nodes[@]}
    logd "[finish_nodes] $n - ${var_nodes[@]}"
    for (( i11 = n - 1; i11 >= 0; i11-- ))
    do
        local node=${var_nodes[i11]}
        logd "[finish_nodes] $app_name node #$i11: $finish_node '$node' '${@}'..."
        $finish_node "$node" "${@}"
    done
}

print_disk_usage() {
    local msg=$1
    local path=$2
    [[ -n "${msg}" ]] && echo "${msg}"
    cd "${path}" && df -h . && du -hs *
}

print_free_mem() {
    free
}

print_cpu_info() {
    lscpu || cat /proc/cpuinfo
}

cat_files() {
    local path=$1
    local p_file
    for p_file in $(ls "${path}")
    do
        if [[ -f "${path}/$p_file" ]]
        then
            echo -n "$p_file: "
            cat "${path}/$p_file"
        fi
    done
}

print_thp_info() {
    local thp_path
    if [[ -d /sys/kernel/mm/transparent_hugepage ]]
    then
        thp_path=/sys/kernel/mm/transparent_hugepage
    elif [[ -d /sys/kernel/mm/redhat_transparent_hugepage ]]
    then
        thp_path=/sys/kernel/mm/redhat_transparent_hugepage
    fi
    [[ -d "${thp_path}" ]] || return
    echo "THP path: ${thp_path}"
    cat_files ${thp_path}
}

print_sys_info() {
    echo "-------------------- uname ----------------------"
    uname -a
    echo
    echo "-------------------- cpuinfo --------------------"
    print_cpu_info
    echo
    echo "-------------------- thpinfo -------------------"
    print_thp_info
    echo
    echo "-------------------- meminfo --------------------"
    cat /proc/meminfo
    echo
    print_free_mem
    echo
    echo "-------------------- zst ------------------------"
    zing-ps -s |& cat
    echo
    echo "-------------------- ulimit ---------------------"
    ulimit -a
    echo
    echo "-------------------- env ------------------------"
    env
    echo
    echo "-------------------- diskinfo -------------------"
    df -h
    echo
    echo "-------------------- lsblk -------------------"
    lsblk
    echo
    echo "-------------------- sysctl ---------------------"
    sysctl -a |& cat
    echo
}

drop_caches() {
    [[ "$DROP_CACHES" == true ]] || return
    if [[ -f /home/dolphin/taskpool/bin/z_sudo ]]
    then
        log_sep
        log "----------------------------- mem before caches drop --------------------------"
        print_free_mem |& logx ''
        log_sep
        log "Dropping caches..."
        sudo -n /home/dolphin/taskpool/bin/z_sudo drop_caches > /dev/null || return 1
        log "----------------------------- mem after caches drop ---------------------------"
        print_free_mem |& logx ''
        log_sep
    else
        log_sep
        log "----------------------------- mem before caches drop --------------------------"
        print_free_mem |& logx ''log "Cannot drop caches: no z_sudo found"
    fi
}

find_process() {
    local pars="-u $(whoami)"
    local p
    while [[ "$1" == -* ]]
    do
        pars="$pars $1"
        shift
    done
    local args="${@}"
    pgrep $pars "$args"
}

check_process() {
    local pars="-u $(whoami)"
    local p
    while [[ "$1" == -* ]]
    do
        pars="$pars $1"
        shift
    done
    local args="${@}"
    log "pgrep args: $pars '$args'"
    if p=$(pgrep $pars "$args")
    then
        log "Found process: $pars '$args' - ${p}..."
        return 0
    else
        return 1
    fi
}

stop_process() {
    local pars="-u $(whoami)"
    local p
    while [[ "$1" == -* ]]
    do
        pars="$pars $1"
        shift
    done
    local args="${@}"
    log "pgrep args: $pars '$args'"
    if p=$(pgrep $pars "$args")
    then
        log "Killing $pars '$args' - ${p}..."
        pkill $pars "$args"
    fi
    for (( i = 0; i < 30; i++ ))
    do
        p=$(pgrep $pars "$args") || break
        sleep 1
    done
    if p=$(pgrep $pars "$args")
    then
        log "Force killing (--signal 9) $pars '$args' - ${p}..."
        pkill -9 $pars "$args"
        for (( i = 0; i < 30; i++ ))
        do
            if p=$(pgrep $pars "$args")
            then
                sleep 1
            else
                break
            fi
        done
    fi
    if p=$(pgrep $pars "$args")
    then
        log "WARNING: Process(es) still alive $pars '$args' - ${p}..."
    fi
}

wait_for_app_start() {
    local name=$1
    local log=$2
    local msg=$3
    local check_log=${4:-true}
    local wait_time=${5:-${WAIT_TIME:-600}}
    for (( i = 0; i <= wait_time; i += 5 ))
    do
        if [[ "$check_log" == true ]]
        then
            check_jvm_log "$log" || return 1
        fi
        if cat "$log" | grep "$msg"
        then
            log "$name started"
            break
        elif (( i < wait_time ))
        then
            log "Waiting for $name to start ($i/$wait_time)..."
            sleep 5
        else
            log "Failed to start $name"
            return 1
        fi
    done
    return 0
}

start_ipstats() {
    is_true "${USE_IPSTATS}" || return
    local output=${1:-$(pwd)/ipstat.log}
    local hname=${2:-${HOSTNAME}}
    local delay=5
    bash "${SCRIPT_DIR}/ipstats.sh" "${delay}" "${hname}" &> "${output}" &
    log "Started IP stats"
}

start_top() {
    is_true "${USE_TOP}" || return
    local output=${1:-$(pwd)/top.log}
    local hname=${2:-${HOSTNAME}}
    local delay=5
    local start=$(get_stamp)
    log "Starting top..."
    {
    echo "DELAY: ${delay}"
    echo "START: ${start}"
    echo "HOST: ${hname}"
    echo
    top -i -c -b -d ${delay} -w 512
    } &> "${output}" &
    local top_pid=$!
    sleep 1
    if grep "unknown argument 'w'" "${output}"
    then
        kill $top_pid # make sure
        {
        echo "DELAY: ${delay}"
        echo "START: ${start}"
        echo "HOST: ${hname}"
        echo
        top -i -c -b -d ${delay}
        } &> "${output}" &
    fi
    log "Started top"
}

start_mpstat() {
    is_true "${USE_MPSTAT}" || return
    local output=${1:-$(pwd)/mpstat.log}
    local hname=${2:-${HOSTNAME}}
    local delay=5
    local start=$(get_stamp)
    log "Starting mpstat..."
    {
    echo "DELAY: ${delay}"
    echo "START: ${start}"
    echo "HOST: ${hname}"
    echo
    mpstat -P ALL ${delay}
    } &> "${output}" &
    log "Started mpstat"
}

start_diskstats() {
    is_true "${USE_DISKSTATS}" || return
    local output=${1:-$(pwd)/diskstat.log}
    local hname=${2:-${HOSTNAME}}
    local delay=5
    local start=$(get_stamp)
    log "Starting sar for disk stats..."
    {
    echo "DELAY: ${delay}"
    echo "START: ${start}"
    echo "HOST: ${hname}"
    echo
    sar -d -p ${delay}
    } &> "${output}" &
    log "Started sar"
}

start_diskusage() {
    is_true "${USE_DISKSTATS}" || return
    local output=${1:-$(pwd)/diskusage.log}
    local hname=${2:-${HOSTNAME}}
    local delay=5
    local data_dir="$(get_data_dir ${hname})"
    log "Starting disk usage monitor: ${data_dir}..."
    bash "${SCRIPT_DIR}/diskusage.sh" "${data_dir}" "${delay}" "${hname}" &> "${output}" &
    log "Started disk usage monitor"
}

start_vmstat() {
    is_true "${USE_VMSTAT}" || return
    local output=${1:-$(pwd)/vmstat.log}
    local hname=${2:-${HOSTNAME}}
    local delay=60
    local start=$(get_stamp)
    log "Starting vmstat..."
    bash "${SCRIPT_DIR}/vmstat_loop.sh" "${data_dir}" "${delay}" "${hname}" &> "${output}" &
    log "Started sar"
}

start_custom_scripts() {
    [[ -n "${CUSTOM_SCRIPT}" ]] || return
    local p=${CUSTOM_SCRIPT}
    p=${p##*/}
    p=${p%.*}
    log "Starting custom script: ${CUSTOM_SCRIPT}..."
    "${CUSTOM_SCRIPT}"  &> "${1}/${p}.log" &
    log "Started custom script"
}

stop_custom_scripts() {
    [[ -n "${CUSTOM_SCRIPT}" ]] || return
    stop_process -f "^${CUSTOM_SCRIPT}$"
}

check_monitors() {
    if check_process top || \
       check_process sar || \
       check_process -f ipstats.sh
    then
        return 0
    else
        return 1
    fi
}

start_monitor_tools() {
    start_top "$1/top.log"
    start_mpstat "$1/mpstat.log"
    start_ipstats "$1/ipstats.log"
    start_diskstats "$1/diskstats.log"
    start_diskusage "$1/diskusage.log"
    start_vmstat "$1/vmstat.log"
    start_custom_scripts "$1"
}

stop_monitor_tools() {
    [[ "$USE_TOP" == true ]] && stop_process top
    [[ "$USE_MPSTAT" == true ]] && stop_process mpstat
    [[ "$USE_DISKSTATS" == true ]] && stop_process sar
    [[ "$USE_IPSTATS" == true ]] && stop_process -f ipstats.sh
    [[ "$USE_DISKSTATS" == true ]] && stop_process -f diskusage.sh
    [[ "$USE_VMSTAT" == true ]] && stop_process -f vmstat_loop.sh
    stop_custom_scripts
}

wait_for_port() {
    local port=$1
    local name=$2
    local times_cnt=0
    local times_max=${3:-20}
    log "Waiting for ${name}..."
    while ! netstat -lnt | grep -q ${port}
    do
        (( times_cnt++ ))
        if (( times_cnt == times_max ))
        then
            log "Failed to start ${name}!"
            return 1
        fi
        log "Waiting for ${name} on port ${port} (${times_cnt} retry of 10)"
        sleep 2
    done
    log "${name} started on port ${port}"
}

################################################
# Zing configuration helpers
#

zmd_setup() {
    local res_dir=$1
    if [[ -d "$res_dir/pmem-partitions" ]]
    then
        log_cmd "ZMD setup partitions" sudo -n /home/dolphin/taskpool/bin/z_sudo zst-setup-partitions "$res_dir/pmem-partitions" #|| return 1
        mkdir "${res_dir}/pmem-partitions.actual"
        cp /etc/zing/pmem.conf.* "${res_dir}/pmem-partitions.actual"
    fi
    if [[ "$ZMD_RESTART" == "true" ]]
    then
        log_cmd "ZMD stop" sudo -n /home/dolphin/taskpool/bin/z_sudo zmd-stop #|| return 1
        log_cmd "ZMD start" sudo -n /home/dolphin/taskpool/bin/z_sudo zmd-start #|| return 1
    fi
    if [[ "$ZMD_STOP" == "true" ]]
    then
        log_cmd "ZMD stopping..." sudo -n /home/dolphin/taskpool/bin/z_sudo zmd-stop #|| return 1
    fi
    if [[ -n "$HUGE_PAGES" ]]
    then
        log_cmd "Huge pages setup" sudo -n /home/dolphin/taskpool/bin/z_sudo hugepages $HUGE_PAGES $(id -u $USER) || return 1
    fi
    log_cmd "ZST info on setup" "zing-ps -V && zing-ps -s"
    return 0
}

zmd_restore() {
    local res_dir=$1
    if [[ -n "$HUGE_PAGES" ]]
    then
        log_cmd "Huge pages cleanup" sudo -n /home/dolphin/taskpool/bin/z_sudo hugepages 0
    fi
    if [[ "$ZMD_STOP" == "true" ]]
    then
        log_cmd "ZMD start" sudo -n /home/dolphin/taskpool/bin/z_sudo zmd-start #|| return 1
    fi
    if [[ -d "$res_dir/pmem-partitions" ]]
    then
        log_cmd "ZMD restoring partitions" sudo -n /home/dolphin/taskpool/bin/z_sudo zst-restore-partitions "$res_dir/pmem-partitions" #|| return 1
    fi
    log_cmd "ZST info on restore" "zing-ps -V && zing-ps -s"
    return 0
}

################################################
# results processing
#

detect_config() {
    local java="$1/bin/java"
    local opts=$2
    local config=""
    if echo "$opts" | grep -q -- "-XX:+UseFalcon" && echo "$opts" | grep -q -- "-XX:-UseC2"
    then
        config="falcon"
    elif echo "$opts" | grep -q -- "-XX:-UseFalcon" && echo "$opts" | grep -q -- "-XX:+UseC2"
    then
        config="cc2"
    fi
    if echo "$opts" | grep -q -- "-Xmx"
    then
        local heap=$(echo $opts | sed "s|.*-Xmx||;s| .*||;s|g||")
        config="$config heap${heap}"
    fi
    if echo "$opts" | grep -q -- "-XX:ProfileLogIn="
    then
        config="$config profile-in"
    fi
    if echo "$opts" | grep -q -- "-XX:ProfileLogOut="
    then
        config="$config profile-out"
    fi
    if echo "$opts" | grep -q -- "-XX:+ProfilePrintReport"
    then
        config="$config profile-print"
    fi
    if echo "$opts" | grep -q -- "-XX:+UseG1GC"
    then
        config="$config g1"
    fi
    if echo "$opts" | grep -q -- "-XX:+UseConcMarkSweepGC"
    then
        config="$config cms"
    fi
    if echo "$opts" | grep -q -- "-XX:+UseZGC"
    then
        config="$config zgc"
    fi
    if echo "$opts" | grep -q -- "-XX:+UseShenandoahGC"
    then
        config="$config shenandoah"
    fi
    if echo "$opts" | grep -q -- "-XX:+BestEffortElasticity"
    then
        config="$config bee"
    fi
    if [[ -n "${NODES}" ]]
    then
        config="$config nodes_${NODES}"
    fi
    echo $config $CONFIG
}

detect_java_version() {
    local java="${1:-$JAVA_HOME}/bin/java"
    local ver=$($java -version 2>&1 | grep "java version" | sed 's|java version||; s|"||g')
    ver=($ver)
    if [[ "$ver" == 11* ]]
    then
        echo 11
    elif [[ "$ver" == 1.8.* ]]
    then
        echo 8
    fi
}

detect_vm_type() {
    local java="${1:-$JAVA_HOME}/bin/java"
    local opts=$2
    local p=$($java -version 2>&1)
    if echo "$p" | grep -q Zing
    then
        if echo "$opts" | grep -q -- "-XX:+UseFalcon"
        then
            echo zing-dolphin
        elif echo "$opts" | grep -q -- "-XX:+UseC2"
        then
            echo zing-c2
        else
            echo zing
        fi
    elif echo "$p" | grep -q Zulu
    then
        echo zulu
    elif echo "$p" | grep -q HotSpot
    then
        echo oracle
    elif echo "$p" | grep -q OpenJDK
    then
        echo openjdk
    else
        echo unknown
    fi
}

detect_vm_build() {
    local java_home=$1
    if echo "$java_home" | grep -q -- "zvm-dev-"
    then
        echo "$java_home" | sed "s|.*zvm-dev-||; s|/.*||"
    elif echo "$java_home" | grep -q -- "zvm-"
    then
        echo "$java_home" | sed "s|.*zvm-||; s|/.*||"
    elif echo "$java_home" | grep -q -- "/j2sdk/"
    then
        echo "$java_home" | sed "s|.*/j2sdk/||; s|/.*||"
    elif echo "$java_home" | grep -q -- "/jdk"
    then
        echo "$java_home" | sed "s|.*/jdk||; s|/.*||"
    else
        basename "$java_home"
    fi
}

detect_os_name() {
    if [[ -f /etc/system-release ]]
    then
        cat /etc/system-release
    elif [[ -f /etc/os-release ]]
    then
        local name=$(cat /etc/os-release | grep '^NAME="' | sed 's|^NAME="||; s|"||')
        local version=$(cat /etc/os-release | grep '^VERSION="' | sed 's|^VERSION="||; s|"||')
        echo $name $version
    else
        echo Unknown
    fi
}

check_jvm_log() {
    local f=$1
    if tail -10 "$f" | grep -q "Could not create the Java Virtual Machine\|There is insufficient memory\|Error occurred during initialization of VM\|Unable to find java executable" || \
       tail -10 "$f" | grep -q "Hard stop enforced\|Zing VM Error\|java does not meet this requirement\|Could not create the Java Virtual Machine\|Failed to fund AC"
    then
        log "Failed to start JVM. Following error has been reported:"
        echo $LOG_SEP
        tail -10 "$f"
        echo $LOG_SEP
        return 1
    else
        return 0
    fi
}

process_ipstats_log() {
    local tlog=$1
    log "Processing IP stats data file: $tlog ..."
    local json=${tlog/.log/.json}
    local dir_name=$(basename $(dirname "$tlog"))
    local suffix=""
    [[ "$PROCESS_RESULTS" == *force_ipstats* ]] && rm -f "$json"
    if [[ -f "$json" ]]
    then
        log "File already exists: $json"
        return
    fi
    if grep -q "command not found" "$tlog"
    then
        log "Invalid ipstats log!"
        return 1
    fi
    [[ "$dir_name" == node_* ]] && suffix=${dir_name/node/}
    mapfile <"$tlog" data
    local n=${#data[@]}
    (( n--))
    local delay=5
    if [[ "${data[0]}" == DELAY* ]]
    then
        delay=$(echo ${data[0]} | sed "s|.*:||")
    fi
    cat<<EOF > "$json"
{
"doc" : {
"ipstats_data${suffix}" : {
"delay" : $delay,
"rx_tx_data" : [
EOF
    for (( i = 2; i < n; i++ ))
    do
        d=$(echo ${data[$i]})
        echo " [ $d ]," >> "$json"
    done
    d=$(echo ${data[$n]})
    echo " [ $d ]" >> "$json"
    echo "]}}}" >> "$json"
    echo "Generated json file: $json"
    chmod a+w "$json"
    #cat "$json"
}

process_ipstats() {
    local res_dir=${1:-$(pwd)}
    for log in $(find "$res_dir" -name ipstats.log)
    do
        process_ipstats_log "$log"
    done
}

process_top_data_file() {
    local tlog="$1"
    log "Processing top data file: $tlog ..."
    local sys_info="$(dirname "$tlog")/system_info1.log"
    if ! test -f "$sys_info"
    then
        log "Required system_info1.log file not found!"
        return 1
    fi
    local p1="^CPU(s):"
    if procNum=$(echo $(cat "$sys_info" | grep "$p1" | sed "s|.*:[ ]*||"))
    then
        :
    elif procNum=$(echo $(cat "$sys_info" | grep processor | tail -1 | sed "s|.*:||"))
    then
        (( procNum++ ))
    else
        log "Failed to detect CPU number from system_info1.log!"
        return 1
    fi
    log "System CPU num: $procNum"
    log "Processing top data file: $tlog ..."
    local json=${tlog/.log/.json}
    local dir_name=$(basename $(dirname "$tlog"))
    local suffix=""
    [[ "$PROCESS_RESULTS" == *force_topdata* ]] && rm -f "$json"
    if [[ -f "$json" ]]
    then
        log "File already exists: $json"
        return
    fi
    [[ "$dir_name" == node_* ]] && suffix=${dir_name/node/}
    local cpuP="%Cpu(s):"
    local cpuP2="Cpu(s):"
    mapfile <"$tlog" top_data
    local n=${#top_data[@]}
    local N=0
    local javaCpu=0
    local pythonCpu=0
    local arrTotal=0
    local arrJava=0
    local arrPython=0
    for (( i = 0; i < n; i++ ))
    do
        d=${top_data[$i]}
        if [[ "$d" == "$cpuP"* || "$d" == "$cpuP2"* ]]
        then
            (( N++ ))
            if [[ "$d" == "$cpuP"* ]]
            then
                totalCpu=$( echo $d | sed "s|$cpuP||; s| us.*||; s| ||g; s|,|.|;"  )
            else
                totalCpu=$( echo $d | sed "s|$cpuP2||; s|%us.*||; s| ||g; s|,|.|;"  )
            fi
            #echo "$N - $totalCpu $javaCpu $pythonCpu"
            (( javaCpu = javaCpu / procNum ))
            (( pythonCpu = pythonCpu / procNum ))
            arrTotal="$arrTotal, $totalCpu"
            arrJava="$arrJava, $javaCpu"
            arrPython="$arrPython, $pythonCpu"
            javaCpu=0
            pythonCpu=0
        else
            d=( $d )
            first=${d[0]}
            if [[ "$first" == top* || "$first" == Tasks* || "$first" == KiB* || "$first" == PID* || -z "$first" ]]
            then
                continue
            fi
            proc=${d[11]}
            cpu=${d[8]}
            cpu=${cpu/.*/}
            if [[ "$proc" == */java ]]
            then
                (( javaCpu += cpu ))
            fi
            if [[ "$proc" == */python3 ]]
            then
                (( pythonCpu += cpu ))
            fi
        fi
    done
    cat<<EOF > "$json"
{
    "doc" : {
        "top_data${suffix}" : {
            "total_cpu_usage" : [ $arrTotal ],
            "java_cpu_usage" : [ $arrJava ],
            "python_cpu_usage" : [ $arrPython ]
        }
    }
}
EOF
    log "Generated top json file: $json"
    chmod a+w "$json"
    #cat "$json"
}

process_top_data_files() {
    local res_dir=${1:-$(pwd)}
    for top_log in $(find "$res_dir" -name top.log)
    do
        process_top_data_file "$top_log"
    done
}

process_metrics_files() {
    local res_dir=${1:-$(pwd)}
    local json="$res_dir/metrics.json"
    local scores="$res_dir/scores.txt"
    local pargs
    [[ "$PROCESS_RESULTS" == *force_metrics* ]] && rm -f "$json"
    [[ "$PROCESS_RESULTS_PRINT_SCORES" == true ]] && pargs+=" --scores=$scores"
    pargs+=" ${HDR_PROCESS_ARGS}"
    if [[ -f "$json" ]]
    then
        log "File already exists: $json"
        return
    fi
    echo '{ "doc": { "metrics": [' > "$json"
    ${CLIENT_JAVA_HOME}/bin/java -jar ${SCRIPT_DIR}/HdrProcessor.jar $pargs "$res_dir" >> "$json"
    echo ']}}' >> "$json"
    log "Generated metrics in json file: $json"
    chmod a+w "$json"
    #cat "$json"
    [[ -f "$scores" ]] && chmod a+w "$scores"
}

create_run_properties() {
    local res_dir=${1:-$(pwd)}
    local use_log=${2:-false}
    local log_dir=${3:-"$res_dir"}
    local res_dir_abs=$(cd "$res_dir"; pwd)
    logd "Results dir: $res_dir_abs"

    local blog=$(find "$log_dir" -name "run-benchmark.log*")
    local time_file="$res_dir/time_out.log"
    local rally_out=$(find "$res_dir" -name "rally_out_*.log*")
    [[ -f "$rally_out" ]] || rally_out=$(find "$res_dir" -name "rally.log*")
    local zookeeper_out=$(find "$res_dir" -name "zookeeper_server_out.log*")
    local props="$res_dir/run.properties.json"

    local start_time
    local finish_time
    local config
    local hst
    local build
    local build_type
    local vm_type
    local benchmark
    local workload
    local workload_name
    local workload_parameters
    local vm_home
    local vm_args
    local vm_ver
    local client_vm_home
    local client_vm_args
    local application
    local os
    local update_times=true

    if [[ ! -f "$time_file" ]]
    then
        [[ -f "$rally_out" ]] && time_file="$rally_out"
        [[ -f "$zookeeper_out" ]] && time_file="$zookeeper_out"
    fi

    if [[ -f "$time_file" ]]
    then
        log "Using time file: $time_file"
        start_time=$(iso_time $(head -1 "$time_file"))
        finish_time=$(iso_time $(tail -1 "$time_file"))
    elif [[ -e "$ORIG_FILE" ]]
    then
        local file_time=$(stat -c %y "$ORIG_FILE")
        log "Using orig file time: $ORIG_FILE -> $file_time"
        start_time=$(date "+$TIME_FORMAT_Z" -d "$file_time")
    else
        local stamp=$(get_stamp)
        log "Using stamp time: $stamp"
        start_time=$(iso_time $stamp)
        grep start_time "$props" && update_times=false
    fi

    if [[ -f "$props" ]]
    then
        log "Updating existing props file results dir..."
        sed -i "s|\"results_dir\".*:.*\".*\"|\"results_dir\": \"$res_dir_abs\"|" "$props"
        if $update_times
        then
            log "Updating existing props file times..."
            sed -i "s|\"start_time\".*:.*\".*\"|\"start_time\": \"$start_time\"|" "$props"
            sed -i "s|\"finish_time\".*:.*\".*\"|\"finish_time\": \"$finish_time\"|" "$props"
        fi
        cat "$props"
        return
    fi

    if [[ -f "$blog" ]]
    then
        log "Filling basic properties from benchmark log: $blog"
        config=$(echo $(cat $blog | grep 'CONFIG:' | sed -e "s|CONFIG:||"))
        build=$(echo $(cat $blog | grep 'BUILD_NO:' | sed -e "s|BUILD_NO:||"))
        build_type=$(echo $(cat $blog | grep 'BUILD_TYPE:' | sed -e "s|BUILD_TYPE:||"))
        vm_type=$(echo $(cat $blog | grep 'VM_TYPE:' | sed -e "s|VM_TYPE:||"))
        vm_ver=$(echo $(cat $blog | grep 'JDK_VERSION:' | sed -e "s|JDK_VERSION:||"))
    fi

    if [[ "$use_log" == true ]] && [[ -f "$blog" ]]
    then
        log "Getting run properties from benchmark log..."
        hst=$(echo $(cat $blog | grep 'HOST:' | sed -e "s|HOST:||"))
        benchmark=$(echo $(cat $blog | grep 'BENCHMARK:' | sed -e "s|BENCHMARK:||"))
        workload=$(echo $(cat $blog | grep 'WORKLOAD:' | sed -e "s|WORKLOAD:||"))
        workload_name=$(echo $(cat $blog | grep 'WORKLOAD_NAME:' | sed -e "s|WORKLOAD_NAME:||"))
        workload_parameters=$(echo $(cat $blog | grep 'WORKLOAD_PARAMETERS:' | sed -e "s|WORKLOAD_PARAMETERS:||"))
        vm_home=$(echo $(cat $blog | grep 'JAVA_HOME:' | sed -e "s|JAVA_HOME:||"))
        vm_args=$(echo $(cat $blog | grep 'VM_ARGS:' | sed -e "s|VM_ARGS:||"))
    elif [[ "$use_log" != true ]]
    then
        log "Benchmark log file not found in the results dir - creating run properties..."
        if [[ ! -f "$blog" ]]
        then
            config=$(detect_config "$JAVA_HOME" "$JAVA_OPTS")
            build=$(detect_vm_build "$JAVA_HOME")
            init_java_type
            vm_type=$JAVA_TYPE
            vm_ver=$JAVA_VERSION
        fi
        hst=${HOSTNAME}
        os=$(detect_os_name)
        application=$APP_NAME
        benchmark="$BENCHMARK"
        workload="$BENCHMARK_WORKLOAD"
        [[ -n "$BENCHMARK_PARAMETERS" ]] && workload="$workload//$BENCHMARK_PARAMETERS"
        workload_name="$BENCHMARK_WORKLOAD"
        workload_parameters="$BENCHMARK_PARAMETERS"
        vm_home=$JAVA_HOME
        vm_args=$JAVA_OPTS
        client_vm_home=$CLIENT_JAVA_HOME
        client_vm_args=$CLIENT_JAVA_OPTS
    else
        log "Cannot create run properties from benchmark log!"
        return 1
    fi

    cat<<EOF > "$props"
{ "doc" : { "run_properties": {
  "config": "$config",
  "host": "$hst",
  "build": "$build",
  "build_type": "$build_type",
  "vm_type": "$vm_type",
  "vm_home": "$vm_home",
  "vm_args": "$vm_args",
  "vm_version": "$vm_ver",
  "client_vm_home": "$client_vm_home",
  "client_vm_args": "$client_vm_args",
  "os": "$os",
  "application": "$application",
  "benchmark": "$benchmark",
  "workload": "$workload",
  "workload_name": "$workload_name",
  "workload_parameters" : "$workload_parameters",
  "results_dir": "$res_dir_abs",
  "start_time": "$start_time",
  "finish_time": "$finish_time"
}}}
EOF

    log "Run properties created:"
    chmod a+w "$props"
    cat "$props"
}

get_run_id() {
    local res_dir=$1
    local id
    if [[ -f "$res_dir/id" ]]
    then
        id=$(cat "$res_dir/id")
        echo -n $id
        return
    fi
    if [[ -f "$res_dir/run.properties.json" ]]
    then
        id=$(echo $(cat "$res_dir/run.properties.json" | grep "start_time" | sed 's|.*: ||; s|[",:]||g; s|-||g') | sed "s| |T|")Z
    fi
    if [[ -n "$id" ]]
    then
        echo -n $id
        return
    fi
    local time_file="$res_dir/time_out.log"
    if [[ ! -f "$time_file" ]]
    then
        local rally_out=$(find "$res_dir" -name "rally_out_*.log*")
        [[ -f "$rally_out" ]] || rally_out=$(find "$res_dir" -name "rally.log*")
        local zookeeper_out=$(find "$res_dir" -name "zookeeper_server_out.log*")
        [[ -f "$rally_out" ]] && time_file="$rally_out"
        [[ -f "$zookeeper_out" ]] && time_file="$zookeeper_out"
    fi
    if [[ -f "$time_file" ]]
    then
        start_time=$(iso_time $(head -1 "$time_file"))
        id=$(echo $(echo $start_time | sed 's|.*: ||; s|[",:]||g; s|-||g') | sed "s| |T|")Z
    fi
    echo -n $id > "$res_dir/id"
    echo -n $id
}

create_rally_jsons() {
    local res_dir=$1
    local hasResults=false
    for (( race_i = 0; race_i < 1000; race_i++ ))
    do
        [[ -d "$res_dir/benchmarks_${race_i}" ]] || break
        race=$(find "$res_dir/benchmarks_${race_i}" -name race.json)
        [[ -f "$race" ]] || break
        log "Creating Rally jsons #${race_i}..."
        if ! $hasResults
        then
            hasResults=true
            echo "{ \"doc\": { \"races\": [" > $res_dir/races.json
        fi
        (( race_i > 0 )) && echo ',' >> $res_dir/races.json
        cat "$race" >> $res_dir/races.json
    done
    if $hasResults
    then
        echo "]}}" >> $res_dir/races.json
    fi
}

create_doc_jsons() {
    local res_dir=$1
    create_run_properties "$res_dir"
    create_rally_jsons "$res_dir"
#    [[ "$PROCESS_RESULTS" == "" || "$PROCESS_RESULTS" == all* || "$PROCESS_RESULTS" == *ipstats* ]] && process_ipstats "$res_dir"
#    [[ "$PROCESS_RESULTS" == "" || "$PROCESS_RESULTS" == all* || "$PROCESS_RESULTS" == *topdata* ]] && process_top_data_files "$res_dir"
    [[ "$PROCESS_RESULTS" == "" || "$PROCESS_RESULTS" == all* || "$PROCESS_RESULTS" == *metrics* ]] && process_metrics_files "$res_dir"
    if [[ -n "$REPORT_METRICS" ]]
    then
        get_latency_scores "${res_dir}/metrics.json" "$REPORT_METRICS" > "${res_dir}/scores.txt"
    fi
}

upload_basic_doc() {
    local base_url=$1
    local id=$2
    local status=$3
    log "http://dev1:8080/perf/#!?r=$id"
    log "Uploading basic document id: $id..."
    curl "$base_url/$id" -X POST -H "Content-Type: application/json" --data "{ \"trial-timestamp\": \"$id\", \"run-status\": \"$status\" }"
}

upload_doc_jsons() {
    local base_url=$1
    local res_dir=$2
    log "Uploading json documents in $res_dir..."
    for json_file in $(find "$res_dir" -name "*.json")
    do
        if grep -q '"doc"' "$json_file"
        then
            log "Uploading doc '$json_file' to '$base_url'..."
            curl "$base_url" -X POST -H "Content-Type: application/json" --data "@$json_file"
            log
        else
            logd "Not a doc json file: '$json_file'"
        fi
    done
}

upload_basic_result() {
    [[ "$PROCESS_RESULTS" == none ]] && return
    local res_dir=$1
    local dburl=$2
    local preprocess=$3
    local postprocess=$4
    log "Processing results: $res_dir"
    create_doc_jsons "$res_dir" true
    local id=$(get_run_id "$res_dir")
    local status=FAILED
    find "$res_dir" -name REPORT.md | grep REPORT.md && status=PASSED
    log "Uploading doc id: $id"
    [[ -n "$preprocess" ]] && $preprocess "$res_dir"
    if [[ "$PROCESS_RESULTS" != *noupload* ]]
    then
        upload_basic_doc "$dburl" "$id" "$status"
        upload_doc_jsons "$dburl/$id/_update" "$res_dir"
    fi
    [[ -n "$postprocess" ]] && $postprocess "$res_dir"
}

PERF_HOST="dev1.azulsystems.com:8080"

upload_basic_results() {
    local path=$1
    local type=$2
    local preprocess=$3
    local postprocess=$4
    local EXPR='s|.*:||; s|.*"\(.*\)".*|\1|; s|-.*||;'
    log "Processing results recursively: $path"
    find "$path" -name "run.properties.json" | while read -r
    do
        local res_dir=$(dirname $REPLY)
        local type_=${type}
        if [[ "$type_" == unknown || "$type_" == auto ]]
        then
            type_=$(cat run.properties.json | grep '"application"' | sed "$EXPR")
            log "Detected application type from properties: $type_"
        fi
        upload_basic_result "$res_dir" "${PERF_HOST}/perf/benchmarks/$type_" "$preprocess" "$postprocess"
    done
}

upload_results() {
    local type=${1:-unknown}
    local res_dir=${2:-.}
    local preprocess=$3
    local postprocess=$4
    upload_basic_results ${res_dir:-.} "$type" "$preprocess" "$postprocess"
}

workload_list() {
    local base_dir=$1
    local function=$2
    local workloads=$3
    local workloads_list
    local args
    if echo "$workloads" | grep -q '//'
    then
        args=$(echo $workloads | sed "s|.*//||")
        workloads=$(echo $workloads | sed "s|//.*||")
    fi
    if [[ -f "$workloads" || -f "${base_dir}/lists/$workloads" ]]
    then
        if [[ -f "$workloads" ]]
        then
            workloads_list=$(cat "$workloads")
            log "Running workloads: $(echo $workloads_list) ($args) from file list: $workloads"
        else
            workloads_list=$(cat "${base_dir}/lists/$workloads")
            log "Running workloads: $(echo $workloads_list) ($args) from file list: ${base_dir}/lists/$workloads"
        fi
    else
        workloads_list=$workloads
        log "Running workloads: $(echo $workloads_list) ($args)"
    fi
    local w
    for w in $workloads_list
    do
        $function "${w}" "${args}"
    done
}

write_score_on() {
    local score_file=$1; shift
    local name=$1; shift
    local scale=$1; shift
    local score=$1; shift
    name=${name/ /_}
    name=${name/ /_}
    name=${name/ /_}
    echo "Score on $name: $score $scale"
    [[ -n "${score_file}" ]] || return
    echo "Score on $name: $score $scale" >> "${score_file}"
}

write_score_json() {
    local score_json=$1; shift
    local name=$1; shift
    local scale=$1; shift
    local score=$1; shift
    local step=$1; shift
    local host=$1; shift
    local start=$1; shift
    local finish=$1; shift
    [[ -n "${score_json}" ]] || return
    if [[ -f "${score_json}" ]] 
    then
        sed -i '$ d' "${score_json}"
        echo -n "}," >> "${score_json}"
    else
        echo -n '{ "doc": { "scores": [ ' > "${score_json}"
    fi
    cat<<EOF >> "${score_json}"
{
  "name": "$name",
  "unit": "$scale",
  "value": $score,
  "host": "$host",
  "step": $step,
  "duration": $((finish - start)),
  "start": $start,
  "end":   $finish
} ]}}
EOF
}

write_score() {
    write_score_on "$1" "$3" "$4" "$5"
    write_score_json "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
}


list_args() {
    echo --------------------
    for arg in "$*"
    do
        echo "[$arg]"
    done
    echo --------------------
    for arg in "$@"
    do
        echo "[$arg]"
    done
    echo --------------------
}

declare -A var_arg_list

init_workload_name() {
    local wl=$1
    if echo "$wl" | grep -q '//'
    then
        wl=$(echo $wl | sed "s|//.*||")
    fi
    BENCHMARK_WORKLOAD=$wl
}

init_workload_args() {
    local args=$1
    if echo "$args" | grep -q '//'
    then
        args=$(echo $args | sed "s|.*//||")
    else
        args=""
    fi
    BENCHMARK_PARAMETERS=$args
    init_arg_list "$args"
}

init_arg_list() {
    local args=$1
    local k
    for k in "${!var_arg_list[@]}"
    do
        unset var_arg_list[$k]
    done
    IFS=,
    local p=( $args )
    unset IFS
    local n=${#p[@]}
    IFS='='
    for (( i = 0; i < n; i++ ))
    do
        q=( ${p[$i]} )
        local pname=${q[0]}
        local pvalue=${q[1]}
        log "Parsed arg: $pname = $pvalue"
        var_arg_list[$pname]=$pvalue
    done
    unset IFS
}

get_arg() {
    local key=$1
    local defval=$2
    local val=${var_arg_list[$key]}
    if [[ -n "$val" ]]
    then
        log "Param: $key - ${var_arg_list[$key]}" >&2
    else
        val=$defval
        log "Param: $key - $defval (default)" >&2
    fi
    echo $val
}

make_dist() {
    local copy=$1; shift
    local app=$1; shift
    local dist=$1; shift
    rm -f ${app}.zip || exit 1
    zip -r ${app}.zip "${@}" || exit 1
    chmod 444 ${app}.zip
    if [[ "${copy}" == true ]]
    then
        if [[ -f "${dist}/${app}.zip" ]]
        then
            i=0
            while [[ -f "${dist}/${app}.zip.${i}" ]] && (( i < 100 ))
            do
                (( i++ ))
            done
            mv -fv "${dist}/${app}.zip" "${dist}/${app}.zip.${i}"
        fi
        cp -fv ${app}.zip "${dist}" || exit 1
    fi
}

init_java_opts() {
    local java_opts
    java_opts=$(echo "$JAVA_OPTS" | sed "s|__G1__|${JAVA_OPTS_G1}|g;  s|__CMS__|${JAVA_OPTS_CMS}|g;  s|__FALCON__|${JAVA_OPTS_FALCON}|; s|__C2__|${JAVA_OPTS_C2}|; ")
    if [[ "${USE_JHICCUP}" == true ]] && echo "${java_opts}" | grep -qvi jHiccup
    then
        java_opts="${java_opts} __JHICCUP__"
    fi
    JAVA_OPTS=${java_opts}
}

init_java_type() {
    [[ -n "${JAVA_VERSION}" ]] || JAVA_VERSION=$(detect_java_version "$JAVA_HOME")
    [[ -n "${JAVA_TYPE}" ]] || JAVA_TYPE=$(detect_vm_type "$JAVA_HOME")
}

preprocess_java_opts() {
    init_java_type
    local java_opts=${1}
    local dir=${2}
    local name=${3}
    local host=${4:-${HOSTNAME}}
    local script_dir=${5:-${SCRIPT_DIR}}
    local hargs
    [[ -n "${JHICCUP_ARGS}" ]] && hargs="=${JHICCUP_ARGS}"
    local gcargs
    if (( JAVA_VERSION > 8 )) && [[ "${JAVA_TYPE}" != zing* ]]
    then
        gcargs=${JAVA_OPTS_GC_LOG11}
    else
        gcargs=${JAVA_OPTS_GC_LOG}
    fi
#    if [[ $JAVA_TYPE == "zulu" ]]
#    then
#        gcargs=${JAVA_OPTS_GC_LOG11}
#    fi
    java_opts=$(echo "$java_opts" | sed "s|__G1__|${JAVA_OPTS_G1}|g;  s|__CMS__|${JAVA_OPTS_CMS}|g;  s|__FALCON__|${JAVA_OPTS_FALCON}|; s|__C2__|${JAVA_OPTS_C2}|; ")
    java_opts=$(echo "$java_opts" | sed "s|__LOGGC__|${gcargs}|g;  s|__LOGCOMP__|${JAVA_OPTS_COMP_LOG}|g; ")
    java_opts=$(echo "$java_opts" | sed "s|__GC_LOG__|__DIR__/__NAME___%t.%p_gc.log|g")
    java_opts=$(echo "$java_opts" | sed "s|__JHICCUP__|-javaagent:${script_dir}/jHiccup.jar${hargs}|g")
    java_opts=$(echo "$java_opts" | sed "s|__RESET__|-javaagent:${script_dir}/reset-agent.jar=terminateVM=false,timeinterval=${RESET_INTERVAL},iterations=${RESET_ITERATIONS}|g")
    java_opts=$(echo "$java_opts" | sed "s|__DIR__|${dir}|g")
    java_opts=$(echo "$java_opts" | sed "s|__NAME__|${name}|g")
    java_opts=$(echo "$java_opts" | sed "s|__HOST__|${host}|g")
    java_opts=$(echo "$java_opts" | sed "s|__STAMP__|${STAMP}|g")
    java_opts=$(echo "$java_opts" | sed "s|^\s*||")
    echo "${java_opts}"
}

get_java_opts() {
    init_java_opts
    local dir=${1}
    local name=${2}
    local host=${3}
    local script_dir=${4}
    preprocess_java_opts "$JAVA_OPTS $JAVA_BASE_OPTS" "$dir" "$name" "$host" "$script_dir"
}

exclude_java_mem() {
    echo "${@} " | sed "s|-Xmx[^ ]*||"
}

get_java_mem() {
    echo "${@} " | grep -q -- "-Xmx" && echo "${@} " | sed "s|.*-Xmx||; s| .*||"
}

set_property() {
    local file=$1
    local prop=$2
    local value=$3
#    local currValue=$(grep -w -- "$prop" "$file")
    local currValue=$(grep -w -- "^${prop}:\|# ${prop}:" "$file")
    if [[ -z "$currValue" ]]
    then
        log "set_property append: $prop: $value"
        echo >> "$file"
        echo "$prop: $value" >> "$file"
    elif [[ "$currValue" == "# "* ]]
    then
        log "set_property uncomment: $currValue -> $prop: $value"
        sed --in-place "s|# \(\b$prop\b\): .*|\1: $value|" "$file"
    else
        log "set_property change: $currValue -> $prop: $value"
        sed --in-place "s|\(.*\b$prop\b\): .*|\1: $value|" "$file"
    fi
}

set_property_s() {
    local file=$1
    local prop=$2
    local value=$3
    sed --in-place "s|\(.*$prop\): .*|\1: $value|" "$file"
}

write_test_status() {
    local name=$1
    local status=$2
    local time=$3
    [[ -n "$time" ]] && time="spent $time seconds"
    log "Test $name $status $time"
    [[ -d "${RESULTS_DIR}" ]] && echo "$name, $status, $time" >> "${RESULTS_DIR}/status.txt"
}

get_latency_scores() {
    local json=$1
    local metrics=$2
    local nolatency=$3
    IFS=,
    metrics=($metrics)
    unset IFS
    local metric_name
    local metric
    local scale
    local names
    local values
    for metric_name in "${metrics[@]}"
    do
        metric_name=$(echo $metric_name)
        [[ -z "$metric_name" ]] && continue
        names=(` $jq -r '.doc.metrics[] | select(.operation == ''"'$metric_name'"'' and .name == ''"response_times"'') | .percentile_names | .[]' "$json" `)
        values=(` $jq -r '.doc.metrics[] | select(.operation == ''"'$metric_name'"'' and .name == ''"response_times"'') | .percentile_values | .[]' "$json" `)
        scale=` $jq -r '.doc.metrics[] | select(.operation == ''"'$metric_name'"'' and .name == ''"response_times"'') | .scale' "$json" `
        [[ "$scale" == microseconds ]] && scale=us
        [[ "$scale" == milliseconds ]] && scale=ms
        local name
        local value
        local n=${#names[@]}
        echo "#NAMES ${names[@]}"
        for (( i = 0; i < n ; i++ ))
        do
            name=${names[$i]}
            name=$(echo ${name} | sed "s|\\.0$||")
            [[ "$name" == 0 ]] && continue
            value=$(echo ${values[$i]})
            echo "Score on ${metric_name}_${name}th_percentile_latency: ${value} ${scale}"
        done
    done
}

k8s_nodes() {
    log $LOG_SEP
    [[ -n "${@}" ]] && log "${@}"
    kubectl get nodes --output=wide
    kubectl get nodes --show-labels
    log $LOG_SEP
}

k8s_start_worker_nodes() {
    k8s_nodes "Nodes before start:"
    local master=$(kubectl get nodes | grep master | awk '{print $1}')
    log "Starting Kubernetes worker nodes: ${@}, master: ${master}..."
    local cnt=0
    local label=db
    for node in "${@}"
    do
        (( cnt++ ))
        (( cnt > 1 )) && label=perf
        log "Starting worker on host: ${node}, label: ${label}.."
        kubectl delete nodes "${node}"
        host_cmd "${node}" /home/dolphin/taskpool/bin/kubeadm-join.sh "${master}"
        kubectl label nodes "${node}" nodetype=${label} --overwrite
    done
    k8s_nodes "Nodes after start:"
}

k8s_stop_worker_nodes() {
    k8s_nodes "Nodes before stop:"
    local hosts="${@}"
    [[ "${hosts}" == ALL ]] && hosts=$(kubectl get nodes | grep -v master | awk '{print $1}' | sed "s|NAME||")
    if [[ -n "${hosts}" ]]
    then
        log "Stopping Kubernetes working nodes:" $hosts
        kubectl delete nodes ${hosts}
        for node in ${hosts}
        do
            host_cmd "${node}" /home/dolphin/taskpool/bin/kubeadm-reset.sh
        done
        k8s_nodes "Nodes after stop:"
    else
        log "No nodes to stop"
    fi
}

if [[ "$BASH_SOURCE" == "$0" ]]
then
    "$@"
else
    :
fi
