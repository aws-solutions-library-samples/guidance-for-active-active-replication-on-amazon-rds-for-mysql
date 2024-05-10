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

# configureation of ProxySQL based on this note:
# https://proxysql.com/documentation/group-replication-configuration/
# nosemgrep: ifs-tampering 


# Function to display script usage
usage() {
 echo "Usage: $0 [OPTIONS]"
 echo "Options:"
 echo " -h, --help      Display this help message"
 echo " -u, --user      User name for the deployment"
 echo " -p, --password  Password for the deployment"
 echo " -ph, --proxyhostlist  Host list for the deployment"
 echo " -mh, --mysqlhostlist  Host list for the deployment"
 echo " -mp, --mysqlpassword  The password for the application user"
 echo " -mu, --mysqluser  The user name for the application user"
 

}

has_argument() {
    [[ ("$1" == *=* && -n ${1#*=}) || ( ! -z "$2" && "$2" != -*)  ]];
}

extract_argument() {
  echo "${2:-${1#*=}}"
}


test_input(){
  if [[ -z "$user" ]]; then
    #echo "no username setting default"
    user="radmin"
fi
if [[ -z "$password" ]]; then
    #echo "no password setting default"
    password="radmin"
fi

if [[ -z "$proxysqlhostlist" ]] | [[ -z "$mysqlhostlist" ]] ; then
    echo "Empty ProxySQL or MySQL list"
    usage
    exit 2 
fi

if [[ -z "$mysqlpass" ]] | [[ -z "$mysqluser" ]] ; then 
    echo "Empty MySQL Password or MySQL user"
    usage
    exit 2 
fi
}

# Function to handle options and arguments
handle_options() {
  while [[ $# -gt 0 ]]
  do
    case $1 in
      -h | --help)
        usage
        exit 2
        ;;
      -u | --user*)
        user="$2"
        shift 2 
        ;;
      -p | --password*)
        password="$2"
        shift 2
        ;;
      -ph | --proxysqlhostlist*)
        proxysqlhostlist="$2"
        shift 2
        ;; 
      -mh | --mysqlhostlist*)
        mysqlhostlist="$2"
        shift 2
        ;;
      -mu | --mysqluser*)
        mysqluser="$2"
        shift 2
        ;;
      -mp| --mysqlpass*)
        mysqlpass="$2"
        shift 2
        ;;
      --)
        shift;
        break
        ;;
      *)
        echo "Invalid option: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}


# Function to perform the desired actions
get_current_dir() {
SCRIPTDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
TEMPLATEDIR=($SCRIPTDIR/../templates/)
}


# Function to run the SQL command
runCommandProxySQL(){
mysql \
  --user="$user" \
  --password="$password" \
  --host="$proxysqlhost"  \
  --port=6032 \
  --execute="$SQLCOMMAND"
 
}

runCommandMysql(){
mysql \
  --user="$user" \
  --password="$password" \
  --host="$mysqlhost"  \
  --execute="$SQLCOMMAND"
}

#add a new entry into mysql_group_replication_hostgroups bulding 4 hostgroups
# writer_hostgroup (read_only=0),backup_writer_hostgroup(read_only=0 exceeding max_writers),reader_hostgroup (read_only=1),offline_hostgroup
createHostgourp(){
  SQLCOMMAND="INSERT INTO mysql_group_replication_hostgroups (writer_hostgroup,backup_writer_hostgroup,reader_hostgroup,offline_hostgroup,active,max_writers,writer_is_also_reader,max_transactions_behind) VALUES (30,34,31,36,1,3,1,0);"
  runCommandProxySQL
}

cleanHostgourp(){
  SQLCOMMAND="DELETE FROM mysql_group_replication_hostgroups where writer_hostgroup=30;"
  runCommandProxySQL
}

addMysql(){
  SQLCOMMAND="INSERT INTO mysql_servers (hostgroup_id,hostname,port) VALUES (30,'$MYSQLHOST',3306);"
  runCommandProxySQL
}

cleanMyqsl(){
  SQLCOMMAND="DELETE FROM mysql_servers WHERE hostgroup_id BETWEEN 30 AND 39;"
  runCommandProxySQL
}

saveConfig(){
  SQLCOMMAND="LOAD MYSQL SERVERS TO RUNTIME;SAVE MYSQL SERVERS TO DISK;"
  runCommandProxySQL
}

# add user to proxysql 
addMysqlUser(){
  SQLCOMMAND="INSERT INTO mysql_users(username,password,default_hostgroup) VALUES ('$mysqluser','$mysqlpass',30);"
  runCommandProxySQL
}

saveMysqlUser(){
  SQLCOMMAND="LOAD MYSQL USERS TO RUNTIME; SAVE MYSQL USERS TO DISK;"
  runCommandProxySQL
}

# Main script execution
#Set enviermant 
get_current_dir
handle_options "$@"


# test input
test_input

# Perform the desired actions based on the provided flags and arguments
IFS=","
for proxysqlhost in $proxysqlhostlist; do
    echo "ProxySQL is $proxysqlhost"
    echo "clean hostgroups"
    cleanHostgourp
    echo "create hostgroups"
    createHostgourp
    echo "clean all mysqls from hostgroups"
    cleanMyqsl
    echo "adding mysql's to hostgroups"
    for MYSQLHOST in $mysqlhostlist; do
      echo "adding $MYSQLHOST To ProxySQL $proxysqlhost"
      addMysql
    done
    echo "saving MySQL configuration on ProxySQL $proxysqlhost"
    saveConfig
    echo "adding MySQL user to ProxySQL $proxysqlhost"
    addMysqlUser
    saveMysqlUser
done

echo "Done"