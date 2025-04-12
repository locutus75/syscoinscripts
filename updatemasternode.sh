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

tag_url="https://github.com/syscoin/syscoin/releases/latest/"
tag_get="tag_name=v"
tag_grep=$(curl -sL $tag_url | grep -o -m1 "$tag_get\?[0-9]*\.[0-9]*\.[0-9]*")
((tag_pos=${#tag_get}+1))
tag_ver=$(echo "$tag_grep" | cut -c$tag_pos-)

VER=$tag_ver
VER="5.0.1"

echo -e "${PURPLE}Updating Packages${NC}"
sudo apt-get -y update > /dev/null

echo -e "${PURPLE}Updating Syscoin Masternode to version ${VER}${NC}"
sleep 5

echo -e "${CYAN}Shutting down Syscoincore...${NC}"
syscoin-cli stop
echo -e "${CYAN}Please standby...${NC}"
sleep 20

cd $home

if [ -e "~/syscoin-${VER}-x86_64-linux-gnu.tar.gz" ]
then
	echo -e " ${ORANGE}Found old version file, removing${NC}"
        rm -f ~/syscoin-${VER}-x86_64-linux-gnu.tar.gz
else
        echo -e "${GREEN}No old version found, skipping${NC}"
fi

if [ -d "~/syscoin-${VER}" ]
then
        echo -e "${ORANGE}Previous folder found, removing${NC}"
	rm -rf ~/syscoin-${VER}
else
        echo -e "${GREEN}Previous folder not found, skipping.${NC}"
fi

sleep 2

echo -e "${CYAN}Downloading new version ${VER}${NC}"
wget https://github.com/syscoin/syscoin/releases/download/v${VER}/syscoin-${VER}-x86_64-linux-gnu.tar.gz
sleep 2

echo -e "${CYAN}Unpacking...${NC}"
tar xf syscoin-${VER}-x86_64-linux-gnu.tar.gz

echo -e "${CYAN}Installing...${NC}"
sleep 2
sudo install -m 0755 -o root -g root -t /usr/local/bin syscoin-${VER}/bin/*

echo -e "${CYAN}Cleaning up...${NC}"
sleep 2
rm -rf ~/syscoin-${VER}
rm -f ~/syscoin-${VER}-x86_64-linux-gnu.tar.gz

echo -e "${CYAN}Starting Syscoincore...${NC}"
sleep 15
syscoind

echo -e "${CYAN}Please standby...${NC}"
sleep 10

echo -e "${CYAN}Now running SyscoinCore:${ORANGE}"
syscoin-cli -version
syscoin-cli getblockchaininfo | grep \"blocks

# Sentinel has been deprecated since v.5
# echo -e "${PURPLE}Updating Sentinel${NC}"
# cd /root/sentinel
# git pull
# cd ..
rm -rf /root/sentinel
crontab -l | sed '/sentinel/s/^\([^#]\)/#\1/' | crontab -

echo -e "${GREEN}Done.${NC}"
echo -e "${CYAN}Liked it? Syscoin Tippingjar: ${ORANGE}sys1qpqnzpdg4thlktvzgkpazzh3yduh8ctum2eguxe${NC}"
echo -e "${PURPLE}Thanks!${NC}"
