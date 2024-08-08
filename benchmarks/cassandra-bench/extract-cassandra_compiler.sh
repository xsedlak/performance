#!/bin/bash
declare -r MYNAME=$(basename $0)
declare -r MYDIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd -P)

RES_DIR=${1:-$PWD}
WORKLOAD=${2:-workload}

DOUGS_TOOL_DIR=/home/dolphin/console-log-analyzer/build
JAVA_HOME=/home/buildmaster/sw/j2sdk/1.8.0_202/linux/x86_64

#LOGS=`find $RES_DIR \( -name cassandra*comp.log \) $newer_than_filei -print0 | xargs -r -0 ls -1 -t | head -n 1`
LOGS_COUNT=`find $RES_DIR \( -name cassandra*comp.log \) $newer_than_file | grep -v tmp | wc -l`
if [ "$LOGS_COUNT" == "1" ]; then
    exit 1
fi
LOGS=`find $RES_DIR \( -name cassandra*comp.log \) $newer_than_file | grep -v tmp | sort -r | head -n 1`

for LOG in $LOGS; do
# Check wether file actually contain printCompilation & tracedeoptimizations
    echo $LOG
    if ! grep -q -e "installed at .* with size" $LOG; then continue; fi                 # Check if the log contains print compilation
    $JAVA_HOME/bin/java -jar $DOUGS_TOOL_DIR/perflab-reporter.jar $LOG |awk -F ',' -v wl="$WORKLOAD" '{print "Metric " $1 " on " wl ": " $2 " " $3}'|sed 's/num /num_/g'
done
