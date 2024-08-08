#!/bin/bash

strn() {
    local len=$1
    local char=$2
    local str=""
    for ((k=0;k<len;k++))
    do
        str+=$char
    done
    echo $str
}

json_gen() {
local prop=$1
local val=$2
for ((i=0;i<1000;i++))
do
    s=20
    json="{ "
    for ((j=1;j<=s;j++))
    do
    r=$RANDOM
    len=$(( 100 + (r % 1000) ))
    str=$(strn $len $val)
    (( j > 1 )) && json+=", "
    json+="\"${prop}${j}\": \"${str}\""
    done
    json+=" }"
    echo "$json"
done
}

echo risk_payload_1000...
json_gen a A > risk_payload_1000

echo risk_factor_payload_1000...
json_gen b B > risk_factor_payload_1000
