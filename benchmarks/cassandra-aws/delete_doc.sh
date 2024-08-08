#!/bin/bash

type=cassandra

for id in ${@}
do
    echo "Deleting ${type} doc: $id"
    curl localhost:10200/benchmarks/${type}/${id}?pretty -XDELETE
done
