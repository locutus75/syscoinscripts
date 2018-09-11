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

echo -e "${PURPLE}This script will restart Syscoincore and force reindex.${NC}"
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
			echo -e "${CYAN}Manual Installation detected, shutting down Syscoincore${NC}"
			cd $home
			~/syscoin/src/syscoin-cli stop
			sleep 10

			echo -e "${CYAN}Removing old debug.log${NC}"
			if [ -e "/home/$USER/.syscoincore/debug.log" ]
			then
							echo -e " ${GREEN}debug.log found, removing${NC}"
							rm ~/.syscoincore/debug.log
			else
							echo -e " ${ORANGE}no debug.log found, skipping${NC}"
			fi
			sleep 2

			echo -e "${CYAN}Removing previous peers.dat${NC}"
			if [ -e "/home/$USER/.syscoincore/peers.dat" ]
			then
							echo -e " ${GREEN}peers.dat found, removing${NC}"
							rm ~/.syscoincore/peers.dat
			else
							echo -e " ${ORANGE}no peers.dat found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Removing previous Blocks folder${NC}"
			if [ -d "/home/$USER/.syscoincore/blocks" ]
			then
							echo -e " ${GREEN}Blocks folder found, removing${NC}"
							rm -rf ~/.syscoincore/blocks
			else
							echo -e " ${ORANGE}no Blocks folder found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Removing previous Chainstate folder${NC}"
			if [ -d "/home/$USER/.syscoincore/chainstate" ]
			then
							echo -e " ${GREEN}Chainstate found, removing${NC}"
							rm -rf ~/.syscoincore/chainstate
			else
							echo -e " ${ORANGE}no Chainstate folder found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Starting Syscoincore with -reindex parameter${NC}"
			~/syscoin/src/syscoind -reindex
			sleep 15

			echo -e "${CYAN}Now running SyscoinCore:${ORANGE}"
			./syscoin/src/syscoin-cli getinfo | grep \"version
			echo -e "${GREEN}Done.${NC}"
			echo -e "${CYAN}Liked it? Syscoin Tippingjar alias: ${ORANGE}donations${CYAN} or use address ${ORANGE}SRPz8SEEGQ7yXLGuRtMXDYPwagm8JuXrmG${NC}"
			echo -e "${PURPLE}Thanks!${NC}"
	else
			echo -e "${CYAN}Scripted Installation detected, shutting down Syscoincore${NC}"
			cd $home
			sudo service syscoind stop
			sleep 10

			echo -e "${CYAN}Removing old debug.log${NC}"
			if [ -e "/home/syscoin/.syscoincore/debug.log" ]
			then
							echo -e " ${GREEN}debug.log found, removing${NC}"
							sudo rm /home/syscoin/.syscoincore/debug.log
			else
							echo -e " ${ORANGE}no debug.log found, skipping${NC}"
			fi
			sleep 2

			echo -e "${CYAN}Removing previous peers.dat${NC}"
			if [ -e "/home/syscoin/.syscoincore/peers.dat" ]
			then
							echo -e " ${GREEN}peers.dat found, removing${NC}"
							sudo rm /home/syscoin/.syscoincore/peers.dat
			else
							echo -e " ${ORANGE}no peers.dat found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Removing previous Blocks folder${NC}"
			if [ -d "/home/syscoin/.syscoincore/blocks" ]
			then
							echo -e " ${GREEN}Blocks folder found, removing${NC}"
							sudo rm -rf /home/syscoin/.syscoincore/blocks
			else
							echo -e " ${ORANGE}no Blocks folder found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Removing previous Chainstate folder${NC}"
			if [ -d "/home/syscoin/.syscoincore/chainstate" ]
			then
							echo -e " ${GREEN}Chainstate found, removing${NC}"
							sudo rm -rf /home/syscoin/.syscoincore/chainstate
			else
							echo -e " ${ORANGE}no Chainstate folder found, skipping${NC}"
			fi
			sleep 1

			echo -e "${CYAN}Starting Syscoincore${NC}"
			sudo service syscoind start
			sleep 15

			echo -e "${CYAN}Now running SyscoinCore:${ORANGE}"
			syscli getinfo | grep \"version
			echo -e "${GREEN}Done.${NC}"
			echo -e "${CYAN}Liked it? Syscoin Tippingjar alias: ${ORANGE}donations${CYAN} or use address ${ORANGE}SRPz8SEEGQ7yXLGuRtMXDYPwagm8JuXrmG${NC}"
			echo -e "${PURPLE}Thanks!${NC}"
	
	fi
else
      echo -e "${RED}Aborted!${NC}"
fi
