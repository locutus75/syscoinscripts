#!/bin/bash
set -e
clear

# Set up color variables
GREEN='\033[1;32m'
RED='\033[1;31m'
ORANGE='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Get today's date
date_today=$(date +%F)

# Get latest version from GitHub (fallback if detection fails)
tag_url="https://github.com/syscoin/syscoin/releases/latest/"
tag_get="tag_name=v"
tag_grep=$(curl -sL $tag_url | grep -o -m1 "$tag_get\?[0-9]*\.[0-9]*\.[0-9]*")
((tag_pos=${#tag_get}+1))
tag_ver=$(echo "$tag_grep" | cut -c$tag_pos-)

# Use fetched version or default
VER=${tag_ver:-"5.0.3"}

echo -e "${PURPLE}Updating Packages${NC}"
sudo apt-get -y update > /dev/null

echo -e "${PURPLE}Updating Syscoin Masternode to version ${VER}${NC}"
sleep 5

echo -e "${CYAN}Shutting down Syscoincore...${NC}"
syscoin-cli stop
echo -e "${CYAN}Please standby...${NC}"
sleep 20

cd "$HOME"

if [ -e "$HOME/syscoin-${VER}-x86_64-linux-gnu.tar.gz" ]; then
    echo -e "${ORANGE}Found old version file, removing${NC}"
    rm -f "$HOME/syscoin-${VER}-x86_64-linux-gnu.tar.gz"
else
    echo -e "${GREEN}No old version found, skipping${NC}"
fi

if [ -d "$HOME/syscoin-${VER}" ]; then
    echo -e "${ORANGE}Previous folder found, removing${NC}"
    rm -rf "$HOME/syscoin-${VER}"
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
rm -rf "$HOME/syscoin-${VER}"
rm -f "$HOME/syscoin-${VER}-x86_64-linux-gnu.tar.gz"

# Ask the user what to do next
echo -e "${CYAN}Choose an action before restarting SyscoinCore:${NC}"
echo "1) Reindex blockchain (recommended for data integrity issues)"
echo "2) Clean ~/.syscoin except syscoin.conf and reboot"
echo "3) Cancel"
read -rp "Enter your choice [1-3]: " user_choice

case "$user_choice" in
    1)
        echo -e "${CYAN}Starting Syscoincore with reindex...${NC}"
        sleep 5
        syscoind -reindex
        ;;
    2)
        echo -e "${ORANGE}Cleaning ~/.syscoin except syscoin.conf...${NC}"
        find /root/.syscoin -mindepth 1 ! -name 'syscoin.conf' -exec rm -rf {} +
        echo -e "${GREEN}Cleanup complete. Rebooting system...${NC}"
        sleep 3
        reboot
        ;;
    3)
        echo -e "${RED}Cancelled by user. Exiting.${NC}"
        exit 1
        ;;
    *)
        echo -e "${RED}Invalid choice. Exiting.${NC}"
        exit 1
        ;;
esac

echo -e "${CYAN}Please standby...${NC}"
sleep 10

echo -e "${CYAN}Now running SyscoinCore:${ORANGE}"
syscoin-cli -version
syscoin-cli getblockchaininfo | grep \"blocks\"

# Sentinel has been deprecated since v5
rm -rf /root/sentinel
crontab -l | sed '/sentinel/s/^\([^#]\)/#\1/' | crontab -

echo -e "${GREEN}Done.${NC}"
echo -e "${CYAN}Liked it? Syscoin Tippingjar: ${ORANGE}sys1qpqnzpdg4thlktvzgkpazzh3yduh8ctum2eguxe${NC}"
echo -e "${PURPLE}Thanks!${NC}"
