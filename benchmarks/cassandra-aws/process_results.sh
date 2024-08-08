#!/bin/bash

SCRIPT_DIR=$(cd $(dirname ${BASH_SOURCE[0]}) && pwd)

source "$SCRIPT_DIR/tools/utils.sh" || exit 1

get_cassandrad_latency_scores() {
    local res_dir=$1
    local json=${res_dir}/metrics.json
    local props=${res_dir}/run.properties.json
    local metrics=$( grep 'run1-Intended-[-A-Z]*-HDR",' "$json" | sed 's|.*: "||; s|".*|,|' )
    local pref=unknown
    if [[ -f "$props" ]]
    then
        pref=$(grep '"workload_name"' "$props" | sed 's|.*: "||; s|".*||')
        local params=$(grep '"workload_parameters"' "$props" | sed 's|.*: "||; s|".*||; s|=||g; s|,|_|g')
        [[ "$params" ]] && pref+="-${params}"
    fi
    log "Extracting metrics $metrics..." >&2
    get_latency_scores "$json" "$metrics" true | grep -v 5th_ | sed "s|run1-|${pref}-|; s|_latency||; s|Intended-||; s|HDR_||;" | tee "${res_dir}/scores.txt"
}

find_latency_scores() {
    local res_dir=$1
    if [[ -f "${res_dir}/results.txt" ]]
    then
        local log="${res_dir}/results.txt"
        {
        cat $log | grep "...high-bound found" | sed 's|.* ...high-bound found: |Score on HighBound: |g' | sed 's|$| msgs/s|g'
        cat $log | grep "...max rate found" | sed 's|.* ...max rate found: |Score on MaxRate: |g' | sed 's|$| msgs/s|g'
        cat $log | grep "SLA for" | grep "broken" | sed 's|.* SLA for |Score on ConformingRate_p|g' | sed 's| percentile = |_|g' | sed 's| ms in |ms_|' | sed 's| ms interval broken on |ms: |g'
        } | tee "${res_dir}/scores.txt"
    else
        [[ "$SCORE_LATENCY" == true ]] && get_cassandrad_latency_scores "${res_dir}"
    fi
}

SCORE_LATENCY=${SCORE_LATENCY:-$2}
PROCESS_RESULTS=${PROCESS_RESULTS:-$3}
upload_results cassandra ${1:-.} find_latency_scores
