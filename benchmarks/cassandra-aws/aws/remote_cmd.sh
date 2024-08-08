#!/bin/bash

SSH_EXT_ARGS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"

h=$1
echo "Remote host: ${h}"
cmd=$2
echo "Remote cmd: ${cmd}"

ssh -i ~/aws-${USER}.pem ${SSH_EXT_ARGS} "${h}" "source /etc/profile; $cmd"
