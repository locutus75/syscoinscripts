#!/bin/bash

#scriptbanpre412nodes.sh version 0.1.0
#thanks to jg@slack

function syscli() { sudo su -c "syscoin-cli $*" syscoin; }

# get the info of all peers

if [ -d "/home/$USER/syscoin/src" ]
then
	peerinfo=$(~/syscoin/src/syscoin-cli getpeerinfo)
else
	peerinfo=$( syscli getpeerinfo )
fi
	# count the number of peers
peercount=$(echo "$peerinfo" | grep "subver" | awk '{ count++ } END { print count }')

# loop through each peer node checking if its version is ok
counter=1
while [ $counter -le $peercount ];
do
  # get the peer
  peer=$(echo $peerinfo | awk -v counter="$counter" -F '} }' '{ print $(counter) }')
  # get the peer's ip
  ip=$(echo $peer | awk -F ':' '{ print $3 }' | awk -F '"' '{ print $2 }')
  # get the overall version string
  ver=$(echo $peer | awk -F '/' '{ print $2 }')
  # if the version is not 4.1.2 then ban the node for one week (in seconds)
  if [ $ver != "Satoshi:4.1.2" ]
  then
  	if [ -d "/home/$USER/syscoin/src" ]
		then
		    	~/syscoin/src/syscoin-cli setban $ip add 604800
		else
		    	syscli setban $ip add 604800
  	fi
	date
 	echo "Found " $ver " - Bye bye" $ip"! See you in a week!"
	echo
fi

  let counter+=1
done
