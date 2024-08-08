#!/bin/bash

source "$(dirname ${BASH_SOURCE[0]})/tools/utils.sh" || exit 1

bench=$(grep BENCHMARK= run.sh | head -1)
bench=${bench/BENCHMARK=/}

git pull || exit 1
make_dist ${1:-true} ${bench} /home/rscherba/dist tests tools workloads \
cassandra-ycsb-config.yaml process_results.sh setupkeys-cassandra-security.sh setup-ycsb-nocompression.cqlsh tests.sh TUSBenchRunner.jar run.sh setup-ycsb.cqlsh nb_data_zip nb
