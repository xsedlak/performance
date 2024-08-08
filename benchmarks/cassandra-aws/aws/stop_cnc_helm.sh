#!/bin/bash

#start it from machine that has helm installed

{
echo "starting cnc server using helm charts..."

PATH=$PATH:/home/isidorkin/temp/helm/linux-amd64/
BASE=/home/dolphin/perflab-runner/
RES_DIR=$(pwd)
CNC_USE_SSL="false"
#CNC_SERVER_PARAMS="helm:perflab-cnc:BROKER3:PERVM30:PERBROKER30:GATEWAY1:CACHE1:WARMUP0"
CNC_SERVER_PARAMS="helm:perflab-coca:BROKER3:PERVM30:PERBROKER30:GATEWAY1:CACHE1:WARMUP0"
NEED_SERVER_START="true"
NEED_SERVER_STOP="false"

source /home/dolphin/perflab-runner/user-scripts/cnc_server.sh

K8S_NAMESPACE="cassandra-isv"
#JAVA_HOME=/home/buildmaster/nightly/ZVM/dev/in_progress/zvm-dev-3829/sandbox/azlinux/jdk11/x86_64/product
JAVA_HOME=/home/buildmaster/nightly/ZVM/dev/in_progress/zvm-dev-3842/sandbox/azlinux/jdk11/x86_64/product

stopServer

} |& tee $(basename ${0%.*})_$(date -u '+%Y%m%d_%H%M%S').log
