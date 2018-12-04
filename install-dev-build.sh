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

echo -e "${PURPLE}Updating Syscoincore Tesnet${NC}"
sleep 1

cd $home

if [ -e "/home/$USER/offlineupdatescript.sh" ]
then
	echo -e " ${GREEN}Found old offlineupdatescript.sh, removing${NC}"
        rm ~/offlineupdatescript.sh
else
        echo -e " ${ORANGE}no offlineupdatescript.sh found, skipping${NC}"
fi
sleep 2

echo -e "${CYAN}Creating temp directory${NC}"
sleep 2
if [ -d "/home/$USER/temp" ]
then
        echo -e "${ORANGE}Temp folder found, skipping${NC}"
else
        mkdir ~/temp
        echo -e "${GREEN}Temp folder created.${NC}"
fi
cd ~/temp
sleep 1

echo -e "${CYAN}Downloading Syscoin-Core master${NC}"
git clone https://github.com/syscoin/syscoin -b dev-3.x-prep-3.1.5
sleep 1

echo -e "${CYAN}Start building${NC}"
cd syscoin
echo -e "    ${CYAN}Generating...${NC}"
sleep 2
./autogen.sh

echo -e "    ${CYAN}Configuring...${NC}"
sleep 2
./configure

echo -e "    ${CYAN}Compiling...${NC}"
sleep 2
make -j$(nproc) -pipe

sleep 2

echo -e "${CYAN}Setting up Sentinel${NC}"
cd src
git clone https://github.com/syscoin/sentinel.git
cd sentinel
sleep 1

echo -e "${CYAN}Copying sentinel.conf${NC}"
cp ~/syscoin/src/sentinel/sentinel.conf ~/temp/syscoin/src/sentinel/sentinel.conf
sleep 2

echo -e "${CYAN}Setting up sentinel${NC}"
virtualenv venv && venv/bin/pip install -r requirements.txt
sleep 5

echo -e "${CYAN}Shutting down Syscoincore${NC}"
cd $home
~/syscoin/src/syscoin-cli stop
sleep 10

echo -e "${CYAN}Checking previous folder${NC}"
sleep 2
if [ -d "/home/$USER/temp/syscoin-previous" ]
then
        echo -e "${GREEN}Previous folder found, renaming to syscoin-"$date_today${NC}
        mv ~/temp/syscoin-previous ~/temp/syscoin-$date_today
else
        echo -e "${ORANGE}No previous update folder found, skipping.${NC}"
fi
sleep 2

echo -e "${CYAN}Moving directories${NC}"
mv ~/syscoin ~/temp/syscoin-previous
sleep 2
mv ~/temp/syscoin ~/syscoin
sleep 2

echo -e "${CYAN}Removing Testnet3 Folder${NC}"
if [ -d "/home/$USER/.syscoincore/testnet3" ]
then
        echo -e " ${GREEN}Testnet3 folder found, removing${NC}"
        rm -rf ~/.syscoincore/testnet3
else
        echo -e " ${ORANGE}no Blocks folder found, skipping${NC}"
fi
sleep 2

echo -e "${CYAN}Starting Syscoincore${NC}"
~/syscoin/src/syscoind
sleep 15

echo -e "${CYAN}Now running SyscoinCore:${ORANGE}"
./syscoin/src/syscoin-cli getinfo | grep \"version
echo -e "${GREEN}Done.${NC}"
echo -e "${CYAN}Liked it? Syscoin Tippingjar alias: ${ORANGE}donations${CYAN} or use address ${ORANGE}SRPz8SEEGQ7yXLGuRtMXDYPwagm8JuXrmG${NC}"
echo -e "${PURPLE}Thanks!${NC}"
