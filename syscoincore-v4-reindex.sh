#!/bin/bash
clear
date_today=$(date +%F)
GREEN='\033[1;32m'
RED='\033[1;31m'
ORANGE='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

echo -e "${PURPLE}This script will restart Syscoincore v4 and force reindex.${NC}"
echo -e "${ORANGE} may take around 30 minutes${NC}"
echo -e "${ORANGE}  your mn status could be going to ${RED}Sentinel_Ping_Expired${ORANGE} but that is normal, it wil be ${GREEN}ENABLED${ORANGE} again within the hour${NC}"
echo
read -e -p "Do you want to continue? [Y/n]: " CONTINUE

if [ "$CONTINUE" = "" ] || [ "$CONTINUE" = "y" ] || [ "$CONTINUE" = "Y" ]; then
        DO_CONTINUE="Y";
fi

if [ "$DO_CONTINUE" = "Y" ]
 then
	if [ -d "/home/$USER/syscoin/src" ]
	then
			echo
			echo -e "${CYAN}Manual Installation detected, shutting down Syscoincore${NC}"
			cd $home
			~/syscoin/src/syscoin-cli stop
			sleep 10

			echo -e "${CYAN}Removing old debug.log${NC}"
			if [ -e "/home/$USER/.syscoin/debug.log" ]
			then
							echo -e " ${GREEN}debug.log found, removing${NC}"
							rm ~/.syscoin/debug.log
			else
							echo -e " ${ORANGE}no debug.log found, skipping${NC}"
			fi
			sleep 2

			echo -e "${CYAN}Removing previous peers.dat${NC}"
			if [ -e "/home/$USER/.syscoin/peers.dat" ]
			then
							echo -e " ${GREEN}peers.dat found, removing${NC}"
							rm ~/.syscoin/peers.dat
			else
							echo -e " ${ORANGE}no peers.dat found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Removing previous Blocks folder${NC}"
			if [ -d "/home/$USER/.syscoin/blocks" ]
			then
							echo -e " ${GREEN}Blocks folder found, removing${NC}"
							rm -rf ~/.syscoin/blocks
			else
							echo -e " ${ORANGE}no Blocks folder found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Removing previous Chainstate folder${NC}"
			if [ -d "/home/$USER/.syscoin/chainstate" ]
			then
							echo -e " ${GREEN}Chainstate found, removing${NC}"
							rm -rf ~/.syscoin/chainstate
			else
							echo -e " ${ORANGE}no Chainstate folder found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Starting Syscoincore with -reindex parameter${NC}"
			~/syscoin/src/syscoind -reindex
			sleep 15

			echo -e "${GREEN}Done.${NC}"
			echo -e "${CYAN}Liked it? Syscoin Tippingjar alias: ${ORANGE}donations${CYAN} or use address ${ORANGE}sys1qwtn246r9pfapmmccr7rncgperjc7qyadc9mz4s${NC}"
			echo -e "${PURPLE}Thanks!${NC}"
	else
			echo -e "${CYAN}Scripted Installation detected, shutting down Syscoincore${NC}"
			cd $home
			sudo service syscoind stop
			sleep 10

			echo -e "${CYAN}Removing old debug.log${NC}"
			if [ -e "/home/syscoin/.syscoin/debug.log" ]
			then
							echo -e " ${GREEN}debug.log found, removing${NC}"
							sudo rm /home/syscoin/.syscoin/debug.log
			else
							echo -e " ${ORANGE}no debug.log found, skipping${NC}"
			fi
			sleep 2

			echo -e "${CYAN}Removing previous peers.dat${NC}"
			if [ -e "/home/syscoin/.syscoin/peers.dat" ]
			then
							echo -e " ${GREEN}peers.dat found, removing${NC}"
							sudo rm /home/syscoin/.syscoin/peers.dat
			else
							echo -e " ${ORANGE}no peers.dat found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Removing previous Blocks folder${NC}"
			if [ -d "/home/syscoin/.syscoin/blocks" ]
			then
							echo -e " ${GREEN}Blocks folder found, removing${NC}"
							sudo rm -rf /home/syscoin/.syscoin/blocks
			else
							echo -e " ${ORANGE}no Blocks folder found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Removing previous Chainstate folder${NC}"
			if [ -d "/home/syscoin/.syscoin/chainstate" ]
			then
							echo -e " ${GREEN}Chainstate found, removing${NC}"
							sudo rm -rf /home/syscoin/.syscoin/chainstate
			else
							echo -e " ${ORANGE}no Chainstate folder found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Starting Syscoincore${NC}"
			sudo service syscoind start
			sleep 15

			echo -e "${GREEN}Done.${NC}"
			echo -e "${CYAN}Liked it? Syscoin Tippingjar alias: ${ORANGE}sys1qwtn246r9pfapmmccr7rncgperjc7qyadc9mz4s${NC}"
			echo -e "${PURPLE}Thanks!${NC}"
	
	fi
else
      echo -e "${RED}Aborted!${NC}"
fi
