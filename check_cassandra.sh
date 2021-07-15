#!/bin/bash
################################################################################
# Script:       check_cassandra.sh                                             #
# Author:       Claudio Kuenzler www.claudiokuenzler.com                       #
# Purpose:      Monitor Cassandra Node and Cluster                             #
# Official doc: www.claudiokuenzler.com/monitoring-plugins/check_cassandra.php #
# License:      GPLv2                                                          #
#                                                                              #
# GNU General Public Licence (GPL) http://www.gnu.org/                         #
# This program is free software; you can redistribute it and/or                #
# modify it under the terms of the GNU General Public License                  #
# as published by the Free Software Foundation; either version 2               #
# of the License, or (at your option) any later version.                       #
#                                                                              #
# This program is distributed in the hope that it will be useful,              #
# but WITHOUT ANY WARRANTY; without even the implied warranty of               #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                #
# GNU General Public License for more details.                                 #
#                                                                              #
# You should have received a copy of the GNU General Public License            #
# along with this program; if not, see <https://www.gnu.org/licenses/>.        #
#                                                                              #
# Copyright 2021 Claudio Kuenzler                                              #
#                                                                              #
# History:                                                                     #
# 20210715: Started plugin development                                         #
################################################################################
# Variables and defaults
STATE_OK=0              # define the exit code if status is OK
STATE_WARNING=1         # define the exit code if status is Warning
STATE_CRITICAL=2        # define the exit code if status is Critical
STATE_UNKNOWN=3         # define the exit code if status is Unknown
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin # Set path
version=0.1
nodetool="/usr/bin/nodetool"

################################################################################
# Functions
help () {
  echo -e "$0 v${version} (c) 2021-$(date +%Y) Claudio Kuenzler / Infiniroot LLC

Usage: ./$0 [-n /path/to/nodetool] -t checktype [-w warn] [-c crit]

Options: 

  *  -t Type of check (mem, cluster)
     -n Path to nodetool command (defaults to /usr/bin/nodetool)
     -w Warning threshold
     -c Critical threshold

* mandatory options

Treshold format for 'mem': int (for percent memory usage)

Check Types:

  mem         Monitor (Java) heap memory usage
  cluster     Monitor nodes in cluster
"
}
################################################################################
# Get user-given variables
while getopts "w:c:t:n:" Input
do
  case ${Input} in
  w)      warning=${OPTARG};;
  c)      critical=${OPTARG};;
  t)      checktype=${OPTARG};;
  n)      nodetool=${OPTARG};;
  *)      help;;
  esac
done
################################################################################
# Check for people who need help - aren't we all nice ;-)
if [ "${1}" = "--help" -o "${#}" = "0" ]; then help; exit $STATE_UNKNOWN; fi
################################################################################
# Check requirements
for cmd in nodetool bc; do
  if ! `which ${cmd} >/dev/null 2>&1`; then
    echo "UNKNOWN: ${cmd} does not exist, please check if command exists and PATH is correct"
    exit ${STATE_UNKNOWN}
  fi
done
################################################################################
# Do checks
case $checktype in

mem) # Check Memory Heap of this node
  info=$(${nodetool} info)
  heap_used=$(echo "$info" | awk -F':' '/^Heap/ {print $2}' | awk -F'/' '{print $1}' | sed "s/ //g")
  heap_cap=$(echo "$info" | awk -F':' '/^Heap/ {print $2}' | awk -F'/' '{print $2}' | sed "s/ //g")
  percent_used=$(echo "$heap_used * 100 / $heap_cap" | bc)

  if [[ -n ${warning} ]] && [[ -n ${critical} ]]; then
    heap_warn=$(echo "${warning} * $heap_cap / 100" | bc)
    heap_crit=$(echo "${critical} * $heap_cap / 100" | bc)
    if [[ $percent_used -ge $critical ]]; then
      echo "CASSANDRA CRITICAL - Used Heap Memory ${percent_used}% (${heap_used}/${heap_cap}) | cassandra_mem=${heap_used}MB;${heap_warn};${heap_crit};0;${heap_cap}"
      exit $STATE_CRITICAL
    elif [[ $percent_used -ge $warning ]]; then
      echo "CASSANDRA WARNING - Used Heap Memory ${percent_used}% (${heap_used}/${heap_cap}) | cassandra_mem=${heap_used}MB;${heap_warn};${heap_crit};0;${heap_cap}"
      exit $STATE_WARNING
    else 
      echo "CASSANDRA OK - Used Heap Memory ${percent_used}% (${heap_used}/${heap_cap}) | cassandra_mem=${heap_used}MB;${heap_warn};${heap_crit};0;${heap_cap}"
      exit $STATE_OK
    fi
  else 
    echo "CASSANDRA OK - Used Heap Memory ${percent_used}% (${heap_used}/${heap_cap}) | cassandra_mem=${heap_used}MB;;;0;${heap_cap}"
    exit $STATE_OK
  fi
;;

cluster) # Check Cassandra Cluster (Nodes availability)
  info=$(${nodetool} status)
  declare -a clusternodes=($(echo "$info" | awk '/%/ {print $2}'))
  declare -a nodestatus=($(echo "$info" | awk '/%/ {print $1}'))

  n=0
  for node in ${clusternodes[*]}; do
    nodestatus=$(echo "$info" | awk '/'"${node}"/' {print $1}')
    nodeid=$(echo "$info" | awk '/'"${node}"/' {print $7}')
    rack=$(echo "$info" | awk '/'"${node}"/' {print $8}')

    if [[ "${nodestatus}" = "UN" ]]; then
      oknodes[$n]="${node} ($rack)"
    elif [[ "${nodestatus}" = "UL" ]] || [[ "${nodestatus}" = "UJ" ]] || [[ "${nodestatus}" = "UM" ]]; then
      warnnodes[$n]="${node} ($rack)"
    elif [[ "D" =~ "{nodestatus}" ]]; then
      critnodes[$n]="${node} ($rack)"
    fi

  let n++
  done

  if [[ ${#critnodes} -gt 0 ]]; then 
    echo "CASSANDRA CRITICAL - Node(s) Down: ${critnodes[*]}, Node(s) OK: ${oknodes[*]}"
    exit $STATE_CRITICAL
  elif [[ ${#warnnodes} -gt 0 ]]; then 
    echo "CASSANDRA WARNING - Node(s) Warning: ${warnnodes[*]}, Node(s) OK: ${oknodes[*]}"
    exit $STATE_WARNING
  else
    echo "CASSANDRA OK - All nodes OK: ${oknodes[*]}"
    exit $STATE_OK
  fi

  echo "found ${#clusternodes[*]}"

;;

esac
