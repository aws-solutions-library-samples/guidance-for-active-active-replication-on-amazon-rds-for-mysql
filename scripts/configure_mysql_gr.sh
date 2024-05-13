#!/bin/bash

# Copyright 2024 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this
# software and associated documentation files (the "Software"), to deal in the Software
# without restriction, including without limitation the rights to use, copy, modify,
# merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
# INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
# PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# This script performs the following actions:

# exsample:
#/scripts/configure_mysql_gr.sh --user admin --password Aa123456 --hostlist "mysql1-replicainstance-****.****.us-east-1.rds.amazonaws.com,mysql2-replicainstance-**.****.rds.amazonaws.com,mysql3-replicainstance-****.****.us-east-1.rds.amazonaws.com"
# Default variable values
# nosemgrep: request-host-used 
# nosemgrep: request-host-used 

# Function to display script usage
usage() {
 echo "Usage: $0 [OPTIONS]"
 echo "Options:"
 echo " -h, --help      Display this help message"
 echo " -u, --user      User name for the deployment"
 echo " -p, --password  Password for the deployment"
 echo " -hl, --hostlist  Host list for the deployment"

}

has_argument() {
    [[ ("$1" == *=* && -n ${1#*=}) || ( ! -z "$2" && "$2" != -*)  ]];
}

extract_argument() {
  echo "${2:-${1#*=}}"
}

# Function to handle options and arguments
handle_options() {
  while [ $# -gt 0 ]; do
    case $1 in
      -h | --help)
        usage
        exit 0
        ;;
      -u | --user*)
        if ! has_argument $@; then
          echo "user not specified." >&2
          usage
          exit 1
        fi
        user=$(extract_argument $@)
        shift
        ;;
      -u | --password*)
        if ! has_argument $@; then
          echo "passowrd not specified." >&2
          usage
          exit 1
        fi
        password=$(extract_argument $@)
        shift
        ;;
      -h | --hostlist*)
        if ! has_argument $@; then
          echo "hostlist not specified." >&2
          usage
          exit 1
        fi
        hostlist=$(extract_argument $@)
        shift
        ;;          
      *)
        echo "Invalid option: $1" >&2
        usage
        exit 1
        ;;
    esac
    shift
  done
}


# Function to perform the desired actions



get_current_dir() {
SCRIPTDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TEMPLATEDIR=($SCRIPTDIR/../templates/)
}


# Function to run the SQL command
runCommand(){
mysql \
  --user="$user" \
  --password="$password" \
  --database="$database" \
  --host="$mysqlinstance"  \
  --execute="$SQLCOMMAND"
}

createUser(){
SQLCOMMAND="call mysql.rds_group_replication_create_user('groupreplication');"
runCommand
}


createChannel(){
SQLCOMMAND="call mysql.rds_group_replication_set_recovery_channel('groupreplication');"
runCommand
}


startReplication(){
SQLCOMMAND="call mysql.rds_group_replication_start(1);"
runCommand
}

addReplication(){
SQLCOMMAND="call mysql.rds_group_replication_start(0);"
runCommand
}

setBinlogRetention(){
  mysql \
  --user="$user" \
  --password="$password" \
  --database="$database" \
  --host="$mysqlinstance"  \
  --execute="call mysql.rds_set_configuration('binlog retention hours',168);"
}

confirmReplication(){
  mysql \
  --user="$user" \
  --password="$password" \
  --database="$database" \
  --host="$mysqlinstance"  \
  --execute="select * from performance_schema.replication_group_members where MEMBER_STATE = 'ONLINE';"
}


stopReplication(){
SQLCOMMAND="call mysql.rds_group_replication_stop();"
runCommand
}

# Main script execution
handle_options "$@"

#Set enviermant 
get_current_dir


# Perform the desired actions based on the provided flags and arguments
# Fix hostlist format
hostlist=${hostlist//,/  }
i=1 
for insatnce in $hostlist; do
    #workaroud naming issues
    mysqlinstance=$insatnce
    echo "the next Host is $mysqlinstance"
    createUser
    createChannel
    setBinlogRetention
    if (( $i == 1 ))
    then
      echo "startReplication Host is $mysqlinstance"
      startReplication  
    else
      echo "addReplication Host is $mysqlinstance"
      addReplication
    fi
    ((i++))
done

# Test replication instance- selecting one of the replicatation instances and counting the number of active node 
confirmReplication

echo "Done"