#!/bin/bash
#
# Predefined command runner
# Usage:
#   $0 pcmd
#   $0 host pcmd
#

SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd -P)
SSH_EXT_ARGS="-o StrictHostKeyChecking=no -o PasswordAuthentication=no"

if [[ -f "${SCRIPT_DIR}/pcmd/${1}" ]]
then
    "${SCRIPT_DIR}/pcmd/${1}"
elif [[ -f "${SCRIPT_DIR}/pcmd/${2}" ]]
then
    ssh ${SSH_EXT_ARGS} "${1}" <<____EOF
    $(cat ${SCRIPT_DIR}/pcmd/${2})
____EOF
fi
