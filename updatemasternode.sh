#!/bin/bash
# Usage: ./updatemasternode.sh [version]
#   version  optional, e.g. 5.1.1 (default: latest GitHub release)
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

BIN_DIR="/usr/local/bin"
DATA_DIR="$HOME/.syscoin"
BACKUP_DIR="$HOME/syscoin-backup-$(date +%F-%H%M%S)"
SERVICE="syscoind"

# Use sudo only when not running as root
SUDO=""
[ "$EUID" -ne 0 ] && SUDO="sudo"

# Ask a yes/no question, returns 0 on yes
confirm() {
    local answer
    read -rp "$1 [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

# True when syscoind is managed by an active systemd service
uses_systemd() {
    command -v systemctl > /dev/null && systemctl is-active --quiet "$SERVICE" 2> /dev/null
}

# Stop syscoind and wait until the process has really exited
stop_node() {
    if uses_systemd; then
        USED_SYSTEMD=1
        $SUDO systemctl stop "$SERVICE"
    else
        syscoin-cli stop || echo -e "${ORANGE}syscoin-cli stop failed, checking if syscoind is running...${NC}"
    fi

    echo -e "${CYAN}Waiting for syscoind to shut down (max 5 minutes)...${NC}"
    for _ in $(seq 1 300); do
        pgrep -x syscoind > /dev/null || return 0
        sleep 1
    done
    return 1
}

# Start syscoind, extra arguments (e.g. -reindex) are passed to syscoind
start_node() {
    if [ -n "$USED_SYSTEMD" ] && [ $# -eq 0 ]; then
        $SUDO systemctl start "$SERVICE" || return 1
    else
        if [ -n "$USED_SYSTEMD" ]; then
            echo -e "${ORANGE}Note: starting syscoind manually with $*, the systemd service stays inactive until the next restart.${NC}"
        fi
        syscoind -daemon "$@" || return 1
    fi

    # Make sure the process is still alive after startup
    sleep 10
    pgrep -x syscoind > /dev/null
}

# Restore the binaries from the backup directory
rollback() {
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR")" ]; then
        echo -e "${RED}No backup available to roll back to.${NC}"
        return 1
    fi
    echo -e "${ORANGE}Restoring previous binaries from ${BACKUP_DIR}...${NC}"
    $SUDO install -m 0755 -o root -g root -t "$BIN_DIR" "$BACKUP_DIR"/*
}

# Determine download architecture
case "$(uname -m)" in
    x86_64)         ARCH="x86_64-linux-gnu" ;;
    aarch64|arm64)  ARCH="aarch64-linux-gnu" ;;
    armv7l)         ARCH="arm-linux-gnueabihf" ;;
    *)
        echo -e "${RED}Unsupported architecture: $(uname -m). Exiting.${NC}"
        exit 1
        ;;
esac

# Determine version: from argument or latest GitHub release (via redirect, no API rate limit)
if [ -n "$1" ]; then
    VER="${1#v}"
else
    latest_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/syscoin/syscoin/releases/latest")
    VER=$(echo "$latest_url" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' | cut -c2-)
fi

if ! [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Could not determine the latest version. Pass it manually, e.g.: $0 5.1.1${NC}"
    exit 1
fi

# Compare with installed version
INSTALLED_VER=$(syscoind -version 2> /dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
echo -e "${PURPLE}Installed version: ${INSTALLED_VER:-unknown}, target version: ${VER}${NC}"

if [ -n "$INSTALLED_VER" ]; then
    if [ "$INSTALLED_VER" = "$VER" ]; then
        confirm "Version ${VER} is already installed. Reinstall anyway?" || { echo -e "${GREEN}Nothing to do.${NC}"; exit 0; }
    elif [ "$(printf '%s\n%s\n' "$INSTALLED_VER" "$VER" | sort -V | tail -n1)" = "$INSTALLED_VER" ]; then
        echo -e "${RED}Warning: ${VER} is OLDER than the installed version ${INSTALLED_VER} (downgrade).${NC}"
        confirm "Continue with downgrade?" || exit 0
    fi
fi

echo -e "${PURPLE}Updating Packages${NC}"
if ! $SUDO apt-get -y update > /dev/null; then
    echo -e "${RED}Package update failed. Exiting.${NC}"
    exit 1
fi

echo -e "${PURPLE}Updating Syscoin Masternode to version ${VER}${NC}"

# Download and verify before stopping the node, to keep downtime minimal
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$WORK_DIR" || { echo -e "${RED}Failed to change to work directory. Exiting.${NC}"; exit 1; }

TARBALL="syscoin-${VER}-${ARCH}.tar.gz"
BASE_URL="https://github.com/syscoin/syscoin/releases/download/v${VER}"

echo -e "${CYAN}Downloading new version ${VER} (${ARCH})${NC}"
if ! wget -q --show-progress "${BASE_URL}/${TARBALL}"; then
    echo -e "${RED}Download failed. Exiting.${NC}"
    exit 1
fi

echo -e "${CYAN}Verifying checksum...${NC}"
if wget -q "${BASE_URL}/SHA256SUMS"; then
    if ! grep -q " ${TARBALL}\$" SHA256SUMS; then
        echo -e "${RED}${TARBALL} not listed in SHA256SUMS. Exiting.${NC}"
        exit 1
    fi
    if ! sha256sum --ignore-missing -c SHA256SUMS; then
        echo -e "${RED}Checksum verification FAILED. Exiting.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Checksum OK.${NC}"
else
    echo -e "${ORANGE}No SHA256SUMS file found for this release, the download cannot be verified.${NC}"
    confirm "Continue without verification?" || exit 1
fi

echo -e "${CYAN}Unpacking...${NC}"
if ! tar xf "$TARBALL"; then
    echo -e "${RED}Extraction failed. Exiting.${NC}"
    exit 1
fi

if ! ls "syscoin-${VER}/bin/"* > /dev/null 2>&1; then
    echo -e "${RED}No binaries found in archive. Exiting.${NC}"
    exit 1
fi

echo -e "${CYAN}Shutting down Syscoincore...${NC}"
if ! stop_node; then
    echo -e "${RED}syscoind did not shut down in time. Exiting without changes.${NC}"
    exit 1
fi

echo -e "${CYAN}Backing up current binaries to ${BACKUP_DIR}...${NC}"
mkdir -p "$BACKUP_DIR"
for bin in "syscoin-${VER}/bin/"*; do
    old="$BIN_DIR/$(basename "$bin")"
    [ -e "$old" ] && cp -p "$old" "$BACKUP_DIR/"
done

echo -e "${CYAN}Installing...${NC}"
if ! $SUDO install -m 0755 -o root -g root -t "$BIN_DIR" "syscoin-${VER}/bin/"*; then
    echo -e "${RED}Install failed.${NC}"
    rollback
    start_node || echo -e "${RED}Failed to restart syscoind.${NC}"
    exit 1
fi

# Ask the user what to do next
echo -e "${GREEN}Choose an action before restarting SyscoinCore:${NC}"
echo "1) Start SyscoinCore normally (default, recommended)"
echo "2) Start with reindex (recommended for data integrity issues)"
echo "3) Clean ~/.syscoin (keeps syscoin.conf and wallets) and reboot"
echo "4) Cancel (SyscoinCore stays STOPPED, masternode will be offline!)"
read -rp "Enter your choice [1-4, default 1]: " user_choice

case "${user_choice:-1}" in
    1)
        echo -e "${CYAN}Starting Syscoincore...${NC}"
        START_ARGS=()
        ;;
    2)
        echo -e "${CYAN}Starting Syscoincore with reindex...${NC}"
        START_ARGS=(-reindex)
        ;;
    3)
        if [ ! -d "$DATA_DIR" ]; then
            echo -e "${RED}${DATA_DIR} not found. Exiting.${NC}"
            exit 1
        fi
        echo -e "${RED}This deletes all blockchain data in ${DATA_DIR} (syscoin.conf, wallet.dat and wallets/ are kept).${NC}"
        read -rp "Type YES to continue: " really
        if [ "$really" != "YES" ]; then
            echo -e "${ORANGE}Cleanup cancelled, starting SyscoinCore normally.${NC}"
            START_ARGS=()
        else
            echo -e "${ORANGE}Cleaning ${DATA_DIR}...${NC}"
            find "$DATA_DIR" -mindepth 1 -maxdepth 1 \
                ! -name 'syscoin.conf' ! -name 'wallet.dat' ! -name 'wallets' \
                -exec rm -rf {} +
            echo -e "${GREEN}Cleanup complete. Rebooting system...${NC}"
            sleep 3
            $SUDO reboot
            exit 0
        fi
        ;;
    4)
        echo -e "${RED}Cancelled by user. SyscoinCore is NOT running, start it with: syscoind -daemon${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice. SyscoinCore is NOT running, start it with: syscoind -daemon${NC}"
        exit 1
        ;;
esac

if ! start_node "${START_ARGS[@]}"; then
    echo -e "${RED}Syscoind failed to start with version ${VER}.${NC}"
    if confirm "Roll back to the previous version (${INSTALLED_VER:-unknown})?"; then
        if rollback && start_node "${START_ARGS[@]}"; then
            echo -e "${GREEN}Rolled back and syscoind is running again.${NC}"
        else
            echo -e "${RED}Rollback failed, please check manually.${NC}"
        fi
    fi
    exit 1
fi

echo -e "${CYAN}Now running SyscoinCore:${ORANGE}"
if ! syscoin-cli -version; then
    echo -e "${RED}Failed to check Syscoin version.${NC}"
fi

syscoin-cli getblockchaininfo | grep \"blocks\" || echo -e "${RED}Could not fetch blockchain info.${NC}"

# Sentinel cleanup
rm -rf /root/sentinel
crontab -l | sed '/sentinel/s/^\([^#]\)/#\1/' | crontab -

echo -e "${GREEN}Done. Previous binaries are backed up in ${BACKUP_DIR}${NC}"
echo -e "${CYAN}Liked it? Syscoin Tippingjar: ${ORANGE}sys1qpqnzpdg4thlktvzgkpazzh3yduh8ctum2eguxe${NC}"
echo -e "${PURPLE}Thanks!${NC}"
