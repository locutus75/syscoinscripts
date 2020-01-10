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

echo -e "${PURPLE}Updating Syscoincore${NC}"
sleep 5

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
sleep 2

echo -e "${CYAN}Downloading Syscoin-Core master${NC}"
git clone https://github.com/syscoin/syscoin -b master
sleep 2

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
sleep 2

echo -e "${CYAN}Copying sentinel.conf${NC}"
cp ~/syscoin/src/sentinel/sentinel.conf ~/temp/syscoin/src/sentinel/sentinel.conf
sleep 2

echo -e "${CYAN}Setting up sentinel${NC}"
virtualenv venv && venv/bin/pip install -r requirements.txt
sleep 5

echo -e "${CYAN}Shutting down Syscoincore${NC}"
cd $home
~/syscoin/src/syscoin-cli stop
sleep 20

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
sleep 5
mv ~/temp/syscoin ~/syscoin
sleep 5

echo -e "${CYAN}Moving previous datadir${NC}"
if [ -d "/home/$USER/.syscoin" ]
then
        echo -e " ${GREEN}Folder found, moving it to ~/temp/.syscoin-previous{NC}"

	if [ -d "/home/$USER/temp/.syscoin-previous" ]
	then
		echo -e "${GREEN}Previous folder found, renaming to ~/temp/.syscoin-"$date_today${NC}
		mv ~/temp/.syscoin-previous ~/temp/.syscoin-$date_today
		mv ~/.syscoin ~/temp/.syscoin-previous
		mkdir ~/.syscoin
	else
		echo -e "${ORANGE}No previous ~/temp/.syscoin-previous folder found.${NC}"
		mv ~/.syscoin ~/temp/.syscoin-previous
		mkdir ~/.syscoin
	fi
else
        echo -e " ${ORANGE}No Previous folder found, something is off here! I suggest you reboot first.${NC}"
	mkdir ~/.syscoin
fi
sleep 5

if [ -e "/home/$USER/temp/.syscoin-previous/syscoin.conf" ]
then
	echo -e "${CYAN}Copying back syscoin.conf${NC}"
	cp ~/temp/.syscoin-previous/syscoin.conf ~/.syscoin/syscoin.conf
else
        echo -e " ${ORANGE}No previous syscoin.conf found, skipping${NC}"
fi
sleep 5

echo -e "${CYAN}Starting Syscoincore...${NC}"
~/syscoin/src/syscoind
echo -e "${CYAN}Please standby...${NC}"
sleep 15

echo -e "${CYAN}Now running SyscoinCore:${ORANGE}"
./syscoin/src/syscoin-cli getnetworkinfo | grep \"subversion
echo -e "${GREEN}Done.${NC}"
echo -e "${CYAN}Liked it? Syscoin Tippingjar: ${ORANGE}sys1qpqnzpdg4thlktvzgkpazzh3yduh8ctum2eguxe${NC}"
echo -e "${PURPLE}Thanks!${NC}"
