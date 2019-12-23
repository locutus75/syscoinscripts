#!/bin/bash

#scriptbanpre410nodes.sh version 0.1.0
#thanks to jg@slack

function syscli() { sudo su -c "syscoin-cli $*" syscoin; }

# get the info of all peers
peerinfo=$( syscli getpeerinfo )
# count the number of peers
peercount=$(echo "$peerinfo" | grep "subver" | awk '{ count++ } END { print count }')

# loop through each peer node checking if its version is lower than 3.0.6
counter=1
while [ $counter -le $peercount ];
do
  # get the peer
  peer=$(echo $peerinfo | awk -v counter="$counter" -F '} }' '{ print $(counter) }')
  # get the peer's ip
  ip=$(echo $peer | awk -F ':' '{ print $3 }' | awk -F '"' '{ print $2 }')
  # get the overall version string
  ver=$(echo $peer | awk -F '/' '{ print $2 }')
  # get the peer's main version
  mainver=$(echo $ver | awk -F '.' '{ print $1 }' | cut -c 14)
  # get the peer's subversion
  subver=$(echo $ver | awk -F '.' '{ print $2 }')
  # get the peer's subsubversion
  subsubver=$(echo $ver | awk -F '.' '{ print $3 }')

  # if the version is lower than 4.1.0 then ban the node for one week (in seconds)
  if [ $mainver -eq 4 ] && [ $subver -eq 1 ] && [ $subsubver -lt 0 ]
  then
    syscli setban $ip add 604800
	date
 	echo $mainver"."$subver"."$subsubver"? BANNED! Bye bye" $ip"! See you in a week!"
	echo
  fi

  let counter+=1
done
