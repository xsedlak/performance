#!/bin/bash

SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd -P)

# ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-20210415 - ami-090717c950a5c34d3

UBUNTU18=ami-07e60b7f43b05d68e     # ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-20220308 - ami-07e60b7f43b05d68e
UBUNTU18_ARM=ami-060412fa7c5879f4c # ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-arm64-server-20220308 - ami-060412fa7c5879f4c
SSH_USER=${SSH_USER:-ubuntu}

AWS_PG="perf-isv-cluster"
AWS_SG="perf-isv-sg"

AWS_ACCT=${AWS_ACCT?Specify AWS_ACCT}
AWS_GROUP=${AWS_GROUP?Specify AWS_GROUP}
ARM=${ARM:-false}

if [[ "$AWS_ACCT" == CNC ]]
then
    AWS_SG_ID=sg-029541ca5d77d9959
    AWS_SUBNET_ID=subnet-0b72b166e724b2e53
    FILE_SYSTEM_ADDRESS=10.21.6.28
elif [[ "$AWS_ACCT" == PRIME ]]
then
    AWS_SG_ID=sg-0ac61a7f5ab1fc3e6
    AWS_SUBNET_ID=subnet-09c3f5344cca8aeff # us-west-2a
    FILE_SYSTEM_ADDRESS=10.22.3.52
else
    echo Unsupported AWS account $AWS_ACCT
    exit 1
fi

echo AWS account $AWS_ACCT

LOCAL_MODE=${LOCAL_MODE:-true}
SSH_EXT_ARGS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"
SSH_SEP="_______________________________________________________________________________"

aws="${SCRIPT_DIR}/tools/aws --profile ${AWS_ACCT}"
jq=${SCRIPT_DIR}/tools/jq

AWS_KEY=${AWS_KEY:-${USER}-test}
aws_key=${SCRIPT_DIR}/keys/${AWS_KEY}-id_rsa # ~/aws-${USER}.pem

my_instances() {
    $aws ec2 describe-instances --filters Name=tag:Department,Values=Performance Name=tag:Group,Values=${AWS_GROUP} Name=key-name,Values="${AWS_KEY}"
}

config_sso() {
    $aws configure sso
}

get_hosts() {
    local hosts=$1
    if [[ "${hosts}" == all ]]
    then
        echo "Getting all hosts..." >&2
        local prop
        if [[ "${LOCAL_MODE}" == true ]]
        then
            prop=.PrivateIpAddress
        else
            prop=.PublicDnsName
        fi
        my_instances | $jq -r '.Reservations[].Instances[]  | select(.State.Name == "running") | ('"${prop}"')'
    else
        echo ${hosts}
    fi
}

get_hosts_u() {
    get_hosts $1 | while read h
    do
        echo ${SSH_USER}@${h}
    done
}

init_perf_opts() {
    echo "Configuring performance parameters"
    tuned-adm profile latency-performance
    sysctl -w vm.swappiness=0
    sysctl -w vm.min_free_kbytes=1048576
    sysctl -w vm.max_map_count=262144
    local thp_path
    if [[ -d /sys/kernel/mm/transparent_hugepage ]]
    then
        thp_path=/sys/kernel/mm/transparent_hugepage
    elif [[ -d /sys/kernel/mm/redhat_transparent_hugepage ]]
    then
        thp_path=/sys/kernel/mm/redhat_transparent_hugepage
    fi
    if [[ -d "${thp_path}" ]]
    then
        echo "THP path: ${thp_path}"
        echo 'never' > ${thp_path}/enabled
        echo 'never' > ${thp_path}/defrag
        echo "THP settings:"
        cat ${thp_path}/enabled
        cat ${thp_path}/defrag
    fi
    swapoff -a
    if ! grep -q "*\s\+-\s\+nofile\s\+65536" /etc/security/limits.conf
    then
      echo "*         -    nofile      65536" >> /etc/security/limits.conf
    #  echo "*         -    nproc       4096" >> /etc/security/limits.conf
    fi
}

print_sys_opts() {
    echo "Printing system parameters:"
    sysctl vm.max_map_count
    sysctl vm.swappiness
    sysctl vm.min_free_kbytes
    tuned-adm active
    ulimit -a
}

power_off() {
    sudo halt -p
}

i_list() {
    echo "Instance summary:"
    my_instances \
    | $jq -c '.Reservations[].Instances[]  | select(.State.Name == "running") | (.InstanceId, .InstanceType, .PrivateIpAddress, .PublicDnsName, .State, .Tags)'
}

i_start() {
    start_instance "${@}"
}

var_ids=""
start_instance() {
    local itype=${1?Missing instance type}
    local icount=${2?Missing instance count}
    local iname=${3?Missing instance name}
    local idisk=${4}
    if !(( icount > 0 && icount < 10 ))
    then
        echo "Unexpected instance count: ${icount}"
        exit 1
    fi
    echo "Starting ${iname} ${icount} ${itype} instance(s)..."
    local img=${UBUNTU18}
    $ARM && img=${UBUNTU18_ARM}
    local out
    [[ -n "${idisk}" ]] && \
    idisk="--block-device-mappings DeviceName=/dev/sdc,Ebs={DeleteOnTermination=true,VolumeSize=${idisk}}"
    echo "Using aws cli: $aws"
    echo "disks: ${disks}"
    echo "arm: ${ARM}"
    echo "image: ${img}"
    if ! out=$( $aws ec2 run-instances --image-id ${img} --count ${icount} --instance-type ${itype} --key-name ${AWS_KEY} \
        --security-group-ids ${AWS_SG_ID} --subnet-id ${AWS_SUBNET_ID} \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Department,Value=Performance},{Key=Lifetime,Value=Hours},{Key=Name,Value='"${iname}"'},{Key=Group,Value='"${AWS_GROUP}"'}]' ${idisk} )
    then
        echo Failed to start instance
        echo "${out}"
        exit 1
    fi
    echo "Start result:"
    echo "${out}"
    local state=$(echo "${out}" | $jq -r '.Instances[0].State')
    local iid=$(echo "${out}" | $jq -r '.Instances[0].InstanceId')
    state=$(echo ${state})
    echo "Started instance: ${iid}"
    [[ -n "${var_ids}" ]] && \
    var_ids+=","
    var_ids+="$iid"
}

copy_keys() {
    local hosts=$1
    local my_key=$(cat ~/.ssh/id_rsa.pub)
    local test_key=$(cat ${SCRIPT_DIR}/keys/${AWS_KEY}-id_rsa.pub)
    local test_key2=$(cat ${SCRIPT_DIR}/keys/rus-id_rsa.pub)
    hosts=$(get_hosts_u "${hosts}")
    for h in ${hosts}
    do
    echo "Copying keys to ${h}..."
    scp -i ${aws_key} ${SSH_EXT_ARGS} ${SCRIPT_DIR}/keys/${AWS_KEY}-id_rsa "${h}:~/.ssh/id_rsa" || exit 1
    scp -i ${aws_key} ${SSH_EXT_ARGS} ${SCRIPT_DIR}/keys/${AWS_KEY}-id_rsa.pub "${h}:~/.ssh/id_rsa.pub" || exit 1
    ssh -i ${aws_key} ${SSH_EXT_ARGS} "${h}" <<EOF
chmod 600 .ssh/id_rsa
$(cat ${SCRIPT_DIR}/pcmd/user)
if ! grep -- "${test_key}" .ssh/authorized_keys
then
    echo "Adding test key..."
    echo "${test_key}" >> .ssh/authorized_keys
fi
if ! grep -- "${test_key2}" .ssh/authorized_keys
then
    echo "Adding test key2..."
    echo "${test_key2}" >> .ssh/authorized_keys
fi
if ! grep -- "${my_key}" .ssh/authorized_keys
then
    echo "Adding my key..."
    echo "${my_key}" >> .ssh/authorized_keys
fi
EOF
    done
}

mount_efs() {
    local hosts=$(get_hosts_u $1)
    for h in ${hosts}
    do
    echo "mount_efs on host $h..."
    {
    ssh -i ${aws_key} ${SSH_EXT_ARGS} "${h}" <<____EOF
    echo ${SSH_SEP}
    echo FILE_SYSTEM_ID=${FILE_SYSTEM_ID}
    echo FILE_SYSTEM_ADDRESS=${FILE_SYSTEM_ADDRESS}
    export FILE_SYSTEM_ID=${FILE_SYSTEM_ID}
    export FILE_SYSTEM_ADDRESS=${FILE_SYSTEM_ADDRESS}
    $(cat ${SCRIPT_DIR}/pcmd/mount_efs)
____EOF
    } |& grep -A 100000 -- "${SSH_SEP}" |& grep -v -- "${SSH_SEP}"
    done
}

init_host() {
    local hosts=$1
    local setup_thp=$2
    local up=$3
    local dev_name=$4
    hosts=$(get_hosts_u "${hosts}")
    for h in ${hosts}
    do
    echo
    echo ----------------------------------------------------------------------------------------------
    echo "Remote host: ${h}"
    echo "Setup THP: ${setup_thp}"
    echo "Update: ${up}"
    echo "Remote disk: ${dev_name}"
    {
    ssh -i ${aws_key} ${SSH_EXT_ARGS} "${h}" <<____EOF
    echo ${SSH_SEP}
    echo "Swapping off..."
    swapoff -a
    echo "Disks:"
    lsblk
    if [[ "$up" == true ]]; then
        $(cat ${SCRIPT_DIR}/pcmd/install_basic_packages)
    fi
    if [[ "${setup_thp}" == true ]]; then
        $(cat ${SCRIPT_DIR}/pcmd/thp_setup_new_kernel)
    fi
    if [[ -n "${dev_name}" ]]; then
        export DEV_NAME="${dev_name}"
        $(cat ${SCRIPT_DIR}/pcmd/mount_dev)
    fi
____EOF
    } |& grep -A 100000 -- "${SSH_SEP}" |& grep -v -- "${SSH_SEP}"
    done
}

init_hosts() {
    init_host "${1}" true true nvme1n1
}

cmd_hosts() {
    local hosts=$(get_hosts_u $1)
    shift
    for h in ${hosts}
    do
    echo "cmd on host $h: ${@}"
    ssh -i ${aws_key} ${SSH_EXT_ARGS} "${h}" "${@}"
    done
}

fix_hosts() {
    local HOSTS="$1"
    shift
    echo "HOSTS:"
    cat "${HOSTS}" || return 1
    HOSTS=$(cat "$HOSTS")
    local hosts=$(get_hosts_u $1)
    shift
    for h in ${hosts}
    do
    echo "Fixing hosts on host $h: ${@}"
    {
    ssh -i ${aws_key} ${SSH_EXT_ARGS} "${h}" <<____EOF
    echo ${SSH_SEP}
    export HOSTS="${HOSTS}"
    $(cat ${SCRIPT_DIR}/pcmd/hosts_append)
____EOF
    } |& grep -A 100000 -- "${SSH_SEP}" |& grep -v -- "${SSH_SEP}"
    done
}

pcmd_hosts() {
    local hosts=$(get_hosts_u $1)
    local pcmd=$2
    echo "PCMD: ${pcmd}"
    [[ -f "${SCRIPT_DIR}/pcmd/${pcmd}" ]] || return 1
    for h in ${hosts}
    do
    echo "PCommand on host $h: ${pcmd}"
    {
    ssh -i ${aws_key} ${SSH_EXT_ARGS} "${h}" <<____EOF
    echo ${SSH_SEP}
    $(cat ${SCRIPT_DIR}/pcmd/${pcmd})
____EOF
    } |& grep -A 100000 -- "${SSH_SEP}" |& grep -v -- "${SSH_SEP}"
    done
}

get_instance_prop() {
    local name=$1
    local prop=$2
    my_instances | $jq -r '.Reservations[].Instances[] | select(.State.Name == "running") | select(.Tags[] == {"Key": "Name", "Value": "'"${name}"'"}) | ('"${prop}"')'
}

make_friendly_hosts() {
    local h
    local hosts_file=hosts.tmp
    > "$hosts_file"
    while read h
    do
        h=( ${h} )
        local hname=${h[0]}
        local hpattern=${h[1]}
        local addrs=( $( get_instance_prop  "${hname}" .PrivateIpAddress ) )
        local naddrs=${#addrs[@]}
        if (( naddrs > 1 )) && [[ "$hpattern" != *__NUM__* ]]
        then
            hpattern+=__NUM__
        fi
        echo "addrs ${naddrs} - ${addrs[@]}"
        for (( i = 1; i <= naddrs; i++ ))
        do
            echo name $hname, pattern $hpattern, hosts entry: ${addrs[$((i-1))]} ${hpattern/__NUM__/${i}}
            echo ${addrs[$((i-1))]} ${hpattern/__NUM__/${i}} >> "$hosts_file"
        done
    done
    fix_hosts "$hosts_file" all
}

copy_license() {
    local hosts=$(get_hosts_u $1)
    shift
    local license=$(cat ${SCRIPT_DIR}/lic/test.lic)
    for h in ${hosts}
    do
    echo "Copying license to host $h"
    {
    ssh -i ${aws_key} ${SSH_EXT_ARGS} "${h}" <<____EOF
    echo ${SSH_SEP}
    sudo mkdir -p /etc/zing || exit 1
    echo "${license}" | sudo tee /etc/zing/license
____EOF
    } |& grep -A 100000 -- "${SSH_SEP}" |& grep -v -- "${SSH_SEP}"
    done
}


if [[ "$BASH_SOURCE" == "${0}" ]]
then
    "${@}"
fi
