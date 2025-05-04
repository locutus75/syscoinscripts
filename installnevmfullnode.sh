#!/bin/bash

# Syscoin NEVM Node Installation Script
# Ensure you run this as a user with sudo privileges

# Variables
SYSCOIN_VERSION="5.0.3"
SYSGETH_VERSION="1.1.4"
INSTALL_DIR="$HOME/syscoin"
CONFIG_DIR="$HOME/.syscoin"

# Create installation directory
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Download Syscoin Core
wget https://github.com/syscoin/syscoin/releases/download/v$SYSCOIN_VERSION/syscoin-$SYSCOIN_VERSION-x86_64-linux-gnu.tar.gz

tar -xzvf syscoin-$SYSCOIN_VERSION-x86_64-linux-gnu.tar.gz
sudo cp syscoin-$SYSCOIN_VERSION/bin/* /usr/local/bin/

# Create syscoin.conf
mkdir -p $CONFIG_DIR
cat > $CONFIG_DIR/syscoin.conf <<EOF
server=1
daemon=1
rpcuser=syscoinrpc
rpcpassword=$(openssl rand -hex 16)
txindex=1
listen=1
rpcallowip=127.0.0.1
rpcbind=127.0.0.1
EOF

# Start Syscoin Core to begin sync
syscoind

echo "Syscoin Core started and syncing..."

# Download and install Syscoin Geth (sysgeth)
cd $INSTALL_DIR
wget https://github.com/syscoin/syscoin/releases/download/v$SYSCOIN_VERSION/sysgeth-linux-amd64.tar.gz

tar -xzvf sysgeth-linux-amd64.tar.gz
sudo cp sysgeth /usr/local/bin/

# Create NEVM directory
mkdir -p $HOME/.sysgeth

# Generate sysgeth config file
cat > $HOME/.sysgeth/config.toml <<EOF
[Node]
DataDir = "$HOME/.sysgeth"
IPCPath = "geth.ipc"
HTTPHost = "127.0.0.1"
HTTPPort = 8545
HTTPModules = ["eth", "net", "web3"]
WSHost = "127.0.0.1"
WSPort = 8546
WSModules = ["eth", "net", "web3"]

[Node.P2P]
ListenAddr = ":30303"
MaxPeers = 50

[Eth]
SyncMode = "full"
NetworkId = 57

[Eth.TxPool]
Locals = []
NoLocals = true
EOF

# Create service scripts to manage the node
cat > $INSTALL_DIR/start_node.sh <<EOF
#!/bin/bash
syscoind &
sysgeth --config $HOME/.sysgeth/config.toml &
EOF

chmod +x $INSTALL_DIR/start_node.sh

# Create a node status script
cat > $INSTALL_DIR/status_node.sh <<EOF
#!/bin/bash
echo "Syscoin Core Sync Status:"
syscoin-cli getblockchaininfo | grep verificationprogress

echo -e "\nSyscoin NEVM Geth Status:"
curl -X POST --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' http://localhost:8545
EOF

chmod +x $INSTALL_DIR/status_node.sh

# Inform user
cat <<EOL

Installation Complete!

- Use "$INSTALL_DIR/start_node.sh" to start both Syscoin Core and Syscoin Geth.
- Use "$INSTALL_DIR/status_node.sh" to check sync status.

Your Syscoin NEVM node is now syncing!

EOL
