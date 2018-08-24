#!/bin/bash
echo "Updating Syscoincore..."
echo "Creating temp directory"
mkdir ~/temp && cd ~/temp && git clone https://github.com/syscoin/syscoin -b master

echo "Start building."
cd syscoin && ./autogen.sh && ./configure && make -j$(nproc) -pipe

echo "Setting up Sentinel"
cd src && git clone https://github.com/syscoin/sentinel.git && cd sentinel

echo "Copying sentinel.conf"
cp ~/syscoin/src/sentinel/sentinel.conf ~/temp/syscoin/src/sentinel/sentinel.conf 

echo "Setting up sentinel"
virtualenv venv && venv/bin/pip install -r requirements.txt

echo "Shutting down core"
cd $home && ~/syscoin/src/syscoin-cli stop
sleep 7

echo "Moving directories."
mv ~/syscoin/ ~/temp/syscoin-previous && mv ~/temp/syscoin/ ~/syscoin && rm ~/.syscoincore/debug.log

echo "Starting Syscoincore"
~/syscoin/src/syscoind
