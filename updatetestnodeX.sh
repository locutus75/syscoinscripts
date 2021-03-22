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

echo -e "${PURPLE}Updating Syscoin Testnode RC$ $1{NC}"
sleep 5

echo -e "${CYAN}Shutting down Syscoincore...${NC}"
syscoin-cli stop
echo -e "${CYAN}Please standby...${NC}"
sleep 10

cd $home

echo -e "${CYAN}Downloading new Testnode RC$ $1{NC}"
wget https://github.com/syscoin/syscoin/releases/download/v4.2.0rc$1/syscoin-4.2.0rc$1-x86_64-linux-gnu.tar.gz
sleep 2

echo -e "${CYAN}Unpacking...${NC}"
tar xf syscoin-4.2.0rc$1-x86_64-linux-gnu.tar.gz

echo -e "${CYAN}Installing...${NC}"
sleep 2
sudo install -m 0755 -o root -g root -t /usr/local/bin syscoin-4.2.0rc$1/bin/*

echo -e "${CYAN}Cleaning up...${NC}"
sleep 2
rm -r syscoin-4.2.0rc$1
rm ~/syscoin-4.2.0rc$1-x86_64-linux-gnu.tar.gz

echo -e "${CYAN}Starting Syscoincore...${NC}"
sleep 2
rm -r ~/.syscoin/testnet3/blocks
rm -r ~/.syscoin/testnet3/chainstate
sleep 2
syscoind

echo -e "${CYAN}Please standby...${NC}"
sleep 15

echo -e "${CYAN}Now running SyscoinCore:${ORANGE}"
syscoin-cli getnetworkinfo | grep \"subversion
syscoin-cli getblockchaininfo | grep \"blocks

echo -e "${GREEN}Done.${NC}"
echo -e "${CYAN}Liked it? Syscoin Tippingjar: ${ORANGE}sys1qpqnzpdg4thlktvzgkpazzh3yduh8ctum2eguxe${NC}"
echo -e "${PURPLE}Thanks!${NC}"
