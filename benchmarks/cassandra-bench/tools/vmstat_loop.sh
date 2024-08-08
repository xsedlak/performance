#!/bin/bash

SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)

get_stamp() {
    local p=$(date -u "+%Y-%m-%d %H:%M:%S,%N")
    echo ${p::23},UTC
}

DATA_DIR=${1}
DELAY=${2:-5}
HOST=${3:-$HOSTNAME}
START=$(get_stamp)

no=0

echo "DATA_DIR: ${DATA_DIR}"
echo "DELAY: ${DELAY}"
echo "START: ${START}"
echo "HOST: ${HOST}"
echo

while true
do
    (( no++ ))
    echo $(get_stamp) - ${no}
    vmstat
    sleep "$DELAY"
    echo
done
