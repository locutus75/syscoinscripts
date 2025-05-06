#!/bin/bash
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
if ! sudo apt-get -y update > /dev/null; then
    echo -e "${RED}Package update failed. Exiting.${NC}"
    exit 1
fi

echo -e "${PURPLE}Updating Syscoin Masternode to version ${VER}${NC}"
sleep 5

echo -e "${CYAN}Shutting down Syscoincore...${NC}"
if ! syscoin-cli stop; then
    echo -e "${RED}Failed to stop syscoin-cli. Continuing anyway...${NC}"
fi

echo -e "${CYAN}Please standby...${NC}"
sleep 20

cd "$HOME" || { echo -e "${RED}Failed to change to home directory. Exiting.${NC}"; exit 1; }

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
if ! wget https://github.com/syscoin/syscoin/releases/download/v${VER}/syscoin-${VER}-x86_64-linux-gnu.tar.gz; then
    echo -e "${RED}Download failed. Exiting.${NC}"
    exit 1
fi
sleep 2

echo -e "${CYAN}Unpacking...${NC}"
if ! tar xf syscoin-${VER}-x86_64-linux-gnu.tar.gz; then
    echo -e "${RED}Extraction failed. Exiting.${NC}"
    exit 1
fi

echo -e "${CYAN}Installing...${NC}"
sleep 2
if ! sudo install -m 0755 -o root -g root -t /usr/local/bin syscoin-${VER}/bin/*; then
    echo -e "${RED}Install failed. Exiting.${NC}"
    exit 1
fi

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
        if ! syscoind -reindex; then
            echo -e "${RED}Syscoind failed to start with reindex.${NC}"
            exit 1
        fi
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
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice. Exiting.${NC}"
        exit 1
        ;;
esac

echo -e "${CYAN}Please standby...${NC}"
sleep 10

echo -e "${CYAN}Now running SyscoinCore:${ORANGE}"
if ! syscoin-cli -version; then
    echo -e "${RED}Failed to check Syscoin version.${NC}"
fi

syscoin-cli getblockchaininfo | grep \"blocks\" || echo -e "${RED}Could not fetch blockchain info.${NC}"

# Sentinel cleanup
rm -rf /root/sentinel
crontab -l | sed '/sentinel/s/^\([^#]\)/#\1/' | crontab -

echo -e "${GREEN}Done.${NC}"
echo -e "${CYAN}Liked it? Syscoin Tippingjar: ${ORANGE}sys1qpqnzpdg4thlktvzgkpazzh3yduh8ctum2eguxe${NC}"
echo -e "${PURPLE}Thanks!${NC}"
