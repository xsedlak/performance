#!/bin/bash

TARGET_RATE=${TARGET_RATE:-100k}
TEST_TIME=${TEST_TIME:-10m}
RESULTS_DIR=${RESULTS_DIR:-/res_dir}
MASTER_PORT=${MASTER_PORT:-9042}
MASTER_NODE=${MASTER_NODE:-localhost}
HEAP_SIZE=${HEAP_SIZE:-1g}

while [[ "${1}" == *=* ]]
do
    export "${1}"
    echo Exported "${1}"
    shift
done

echo "Master node: ${MASTER_NODE}:${MASTER_PORT}"
echo "TLP_STRESS_HOME: ${TLP_STRESS_HOME}"
echo "Heap size: ${HEAP_SIZE}"
echo "Target rate: ${TARGET_RATE}"
echo "Test time: ${TEST_TIME}"
echo "Results dir: ${RESULTS_DIR}"

cd "${RESULTS_DIR}/" || exit 1

echo java -Xmx${HEAP_SIZE} -Xms${HEAP_SIZE} \
    -cp "${TLP_STRESS_HOME}/lib/*" com.thelastpickle.tlpstress.MainKt run BasicTimeSeries \
    --duration ${TEST_TIME} --partitions 100M --threads 8 --populate 200000 --readrate 0.2 --rate ${TARGET_RATE} \
    --partitiongenerator sequence --concurrency 50 --port ${MASTER_PORT} --host ${MASTER_NODE} \
    --csv ${RESULTS_DIR}/tlp_stress_metrics_0.csv \
    --hdr ${RESULTS_DIR}/tlp_stress_metrics_0.hdr

java -Xmx${HEAP_SIZE} -Xms${HEAP_SIZE} \
    -cp "${TLP_STRESS_HOME}/lib/*" com.thelastpickle.tlpstress.MainKt run BasicTimeSeries \
    --duration ${TEST_TIME} --partitions 100M --threads 8 --populate 200000 --readrate 0.2 --rate ${TARGET_RATE} \
    --partitiongenerator sequence --concurrency 50 --port ${MASTER_PORT} --host ${MASTER_NODE} \
    --csv ${RESULTS_DIR}/tlp_stress_metrics_0.csv \
    --hdr ${RESULTS_DIR}/tlp_stress_metrics_0.hdr

chmod -R 777 .
