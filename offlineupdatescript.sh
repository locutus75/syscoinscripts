#!/bin/bash
echo "Updating Syscoincore..."
echo "Creating temp directory"
mkdir ~/temp && cd ~/temp && git clone https://github.com/syscoin/syscoin -b master
sleep 1

echo "Start building."
cd syscoin && ./autogen.sh && ./configure && make -j$(nproc) -pipe
sleep 2

echo "Setting up Sentinel"
cd src && git clone https://github.com/syscoin/sentinel.git && cd sentinel
sleep 1

echo "Copying sentinel.conf"
cp ~/syscoin/src/sentinel/sentinel.conf ~/temp/syscoin/src/sentinel/sentinel.conf 
sleep 2

echo "Setting up sentinel"
virtualenv venv && venv/bin/pip install -r requirements.txt
sleep 5

echo "Shutting down Syscoincore"
cd $home && ~/syscoin/src/syscoin-cli stop
sleep 10

echo "Moving directories."
mv ~/syscoin/ ~/temp/syscoin-previous && mv ~/temp/syscoin/ ~/syscoin && rm ~/.syscoincore/debug.log
sleep 5

echo "Starting Syscoincore"
~/syscoin/src/syscoind
echo "Done. Goodnight."
