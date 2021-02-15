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

echo -e "${PURPLE}Updating Syscoin Testnode${NC}"
sleep 5

echo -e "${CYAN}Shutting down Syscoincore...${NC}"
syscoin-cli stop
echo -e "${CYAN}Please standby...${NC}"
sleep 10

cd $home

if [ -e "/root/syscoin-4.2.0rc5-x86_64-linux-gnu.tar.gz" ]
then
	echo -e "${GREEN}Removing syscoin-4.2.0rc5-x86_64-linux-gnu.tar.gz${NC}"
        rm ~/syscoin-4.2.0rc5-x86_64-linux-gnu.tar.gz
else
        echo -e " ${ORANGE}no syscoin-4.2.0rc5-x86_64-linux-gnu.tar.gz found, skipping${NC}"
fi
sleep 2

echo -e "${CYAN}Downloading new Testnode${NC}"
wget https://github.com/syscoin/syscoin/releases/download/v4.2.0rc6/syscoin-4.2.0rc6-x86_64-linux-gnu.tar.gz
sleep 2

echo -e "${CYAN}Unpacking...${NC}"
tar xf syscoin-4.2.0rc6-x86_64-linux-gnu.tar.gz

echo -e "${CYAN}Installing...${NC}"
sleep 2
sudo install -m 0755 -o root -g root -t /usr/local/bin syscoin-4.2.0rc6/bin/*

echo -e "${CYAN}Cleaning up...${NC}"
sleep 2
rm -r syscoin-4.2.0rc6
rm ~/syscoin-4.2.0rc6-x86_64-linux-gnu.tar.gz

echo -e "${CYAN}Starting Syscoincore...${NC}"
syscoind
echo -e "${CYAN}Please standby...${NC}"
sleep 15

echo -e "${CYAN}Now running SyscoinCore:${ORANGE}"
syscoin-cli getnetworkinfo | grep \"subversion

echo -e "${GREEN}Done.${NC}"
echo -e "${CYAN}Liked it? Syscoin Tippingjar: ${ORANGE}sys1qpqnzpdg4thlktvzgkpazzh3yduh8ctum2eguxe${NC}"
echo -e "${PURPLE}Thanks!${NC}"
