#!/bin/bash

#thanks to jg@slack

# get the info of all peers
peerinfo=$(~/syscoin/src/syscoin-cli getpeerinfo)
# count the number of peers
peercount=$(echo "$peerinfo" | grep "Core" | awk '{ count++ } END { print count }')

# loop through each peer node checking if its version is lower than 3.0.6
unluckyip=0;
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

  # if the version is lower than 3.0.6 then ban the node for one week (in seconds)
  if [ $mainver -eq 3 ] && [ $subver -eq 0 ] && [ $subsubver -lt 6 ]
  then
    ~/syscoin/src/syscoin-cli setban $ip add 604800
    date
    echo $mainver"."$subver"."$subsubver"? BANNED! Bye bye" $ip"! See you in a week!"
    echo  
  fi

  # last node in peer list is the unlucky node
  unluckyip=$ip":8369"
  let counter+=1
done
# disconnect the unlucky node to lure in a deviant node
~/syscoin/src/syscoin-cli disconnectnode $unluckyip
