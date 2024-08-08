#!/bin/bash
AWS_ACCT=CNC AWS_GROUP=cassandra-r5d1 bash start_cassandras.sh r5d.2xlarge
#AWS_ACCT=CNC AWS_GROUP=cassandra-r5d2-zgc bash start_cassandras.sh r5d.2xlarge
#AWS_ACCT=CNC AWS_GROUP=cassandra-r5d3-zing bash start_cassandras.sh r5d.2xlarge

#new io optimized i4i
#AWS_ACCT=CNC AWS_GROUP=cassandra-i4i bash start_cassandras.sh i4i.4xlarge

#ARM64 graviton2
#AWS_ACCT=CNC AWS_GROUP=cassandra-r6gd1 bash start_cassandras.sh arm r6gd.2xlarge

#ARM64 graviton3
#AWS_ACCT=CNC AWS_GROUP=cassandra-c7 bash start_cassandras.sh arm c7.8xlarge

