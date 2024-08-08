#!/bin/bash


ARM=false
#if first param is 'arm' - set ARM var (different EC2 AMI type for x86 and ARM instances) and shift params
if [[ "${1,,}" == arm ]]
then
    echo ARM64 flag detected
    ARM=true
    shift
fi
export ARM

node_type=${1?Node instance type required}

if $ARM
then
    loadgen_type=r6g.2xlarge
else
    loadgen_type=c5.2xlarge
fi

dev_name=nvme1n1
#dev_name=xvdc
start_timeout=120

{
echo "Cassandra node instance type ${node_type}"
./aws-tools.sh start_instance ${loadgen_type} 1 loadgen || exit 1
./aws-tools.sh start_instance ${node_type} 3 cassandra-node || exit 1
#1200
echo Wating ${start_timeout}s...
sleep ${start_timeout}
./aws-tools.sh init_host all true true $dev_name
./aws-tools.sh pcmd_hosts all set_max_map_count
./aws-tools.sh mount_efs all
./aws-tools.sh copy_keys all
./aws-tools.sh copy_license all
./aws-tools.sh make_friendly_hosts <<EOF
cassandra-node node__NUM__-${node_type}
loadgen loadgen-${loadgen_type}
EOF
} |& tee $(basename ${0%.*})_$(date -u '+%Y%m%d_%H%M%S').log
