#!/bin/bash
set -euo pipefail

# Set up color variables
GREEN='\033[1;32m'
RED='\033[1;31m'
ORANGE='\033[1;33m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

usage() {
    cat <<EOF
Usage: $0 [options] [version]

  version               Version to install, e.g. 5.1.1 (default: always the latest stable GitHub release)

Options:
  -a, --action ACTION   Action after install, skips the menu:
                          start   start SyscoinCore normally (default)
                          reindex start with -reindex
                          clean   clean ~/.syscoin (keeps syscoin.conf and wallets) and reboot
                          cancel  leave SyscoinCore stopped
  -y, --yes             Non-interactive: answer yes to all questions
  -f, --force           With --yes: also reinstall the same version, allow downgrades
                        and install without checksum verification
  -u, --upgrade-system  Also run apt-get upgrade (otherwise asked interactively)
  -h, --help            Show this help

Example for cron/automation: $0 --yes --action start
EOF
}

# Parse arguments
ACTION=""
ASSUME_YES=0
FORCE=0
UPGRADE_SYSTEM=0
VER=""
while [ $# -gt 0 ]; do
    case "$1" in
        -a|--action)
            [ $# -ge 2 ] || { echo -e "${RED}--action needs a value.${NC}"; exit 1; }
            ACTION="$2"
            shift
            ;;
        -y|--yes)            ASSUME_YES=1 ;;
        -f|--force)          FORCE=1 ;;
        -u|--upgrade-system) UPGRADE_SYSTEM=1 ;;
        -h|--help)           usage; exit 0 ;;
        -*)                  echo -e "${RED}Unknown option: $1${NC}"; usage; exit 1 ;;
        *)                   VER="${1#v}" ;;
    esac
    shift
done

case "$ACTION" in
    ""|start|reindex|clean|cancel) ;;
    *) echo -e "${RED}Invalid action: ${ACTION}${NC}"; usage; exit 1 ;;
esac

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script as root, e.g.: sudo $0${NC}"
    exit 1
fi

BIN_DIR="/usr/local/bin"
DATA_DIR="$HOME/.syscoin"
BACKUP_DIR="$HOME/syscoin-backup-$(date +%F-%H%M%S)"
SERVICE="syscoind"
USED_SYSTEMD=0
INSTALLED_VER=""
START_ARGS=()

# Ask a yes/no question, returns 0 on yes
confirm() {
    local answer=""
    if [ "$ASSUME_YES" -eq 1 ]; then
        echo "$1 -> yes (--yes)"
        return 0
    fi
    read -rp "$1 [y/N]: " answer || true
    [[ "$answer" =~ ^[Yy]$ ]]
}

# Like confirm, but in non-interactive mode only yes when --force is given
confirm_risky() {
    if [ "$ASSUME_YES" -eq 1 ] && [ "$FORCE" -eq 0 ]; then
        echo "$1 -> no (use --force to allow)"
        return 1
    fi
    confirm "$1"
}

# True when syscoind is managed by an active systemd service
uses_systemd() {
    command -v systemctl > /dev/null && systemctl is-active --quiet "$SERVICE" 2> /dev/null
}

# Stop syscoind and wait until the process has really exited
stop_node() {
    if uses_systemd; then
        USED_SYSTEMD=1
        systemctl stop "$SERVICE" || echo -e "${ORANGE}systemctl stop failed, checking if syscoind is running...${NC}"
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
    if [ "$USED_SYSTEMD" -eq 1 ] && [ $# -eq 0 ]; then
        systemctl start "$SERVICE" || return 1
    else
        if [ "$USED_SYSTEMD" -eq 1 ]; then
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
    install -m 0755 -o root -g root -t "$BIN_DIR" "$BACKUP_DIR"/*
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

# Determine version: from argument, otherwise always the latest stable GitHub release
# (pre-releases such as testnet builds are skipped by GitHub's "latest")
if [ -z "$VER" ]; then
    # 1st try: redirect of /releases/latest (no API rate limit)
    latest_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/syscoin/syscoin/releases/latest" || true)
    VER=$(echo "$latest_url" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' | cut -c2- || true)
    # 2nd try: GitHub API
    if [ -z "$VER" ]; then
        VER=$(curl -fsSL "https://api.github.com/repos/syscoin/syscoin/releases/latest" \
            | grep -oE '"tag_name": *"v[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
    fi
    [ -n "$VER" ] && echo -e "${PURPLE}Latest release on GitHub: ${VER}${NC}"
fi

if ! [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "${RED}Could not determine the latest version. Pass it manually, e.g.: $0 5.1.1${NC}"
    exit 1
fi

# Compare with installed version
INSTALLED_VER=$(syscoind -version 2> /dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
echo -e "${PURPLE}Installed version: ${INSTALLED_VER:-unknown}, target version: ${VER}${NC}"

if [ -n "$INSTALLED_VER" ]; then
    if [ "$INSTALLED_VER" = "$VER" ]; then
        if ! confirm_risky "Version ${VER} is already installed. Reinstall anyway?"; then
            echo -e "${GREEN}Nothing to do.${NC}"
            exit 0
        fi
    elif [ "$(printf '%s\n%s\n' "$INSTALLED_VER" "$VER" | sort -V | tail -n1)" = "$INSTALLED_VER" ]; then
        echo -e "${RED}Warning: ${VER} is OLDER than the installed version ${INSTALLED_VER} (downgrade).${NC}"
        confirm_risky "Continue with downgrade?" || exit 0
    fi
fi

# Optional OS package upgrade; a failure here does not abort the Syscoin update
if [ "$UPGRADE_SYSTEM" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    confirm "Also upgrade the system packages (apt-get upgrade)?" && UPGRADE_SYSTEM=1
fi
if [ "$UPGRADE_SYSTEM" -eq 1 ]; then
    echo -e "${PURPLE}Upgrading system packages${NC}"
    if ! { apt-get -y update > /dev/null && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null; }; then
        echo -e "${ORANGE}Package upgrade failed, continuing with the Syscoin update.${NC}"
    fi
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
# Syscoin publishes the checksums as SHA256SUMS.asc (plain list), older/other releases may use SHA256SUMS
SUMS_FILE=""
for f in SHA256SUMS.asc SHA256SUMS; do
    if wget -q "${BASE_URL}/${f}"; then
        SUMS_FILE="$f"
        break
    fi
done

if [ -n "$SUMS_FILE" ]; then
    if ! grep -E "^[0-9a-fA-F]{64}  \*?${TARBALL}\$" "$SUMS_FILE" > "${TARBALL}.sha256"; then
        echo -e "${RED}${TARBALL} not listed in ${SUMS_FILE}. Exiting.${NC}"
        exit 1
    fi
    if ! sha256sum -c "${TARBALL}.sha256"; then
        echo -e "${RED}Checksum verification FAILED. Exiting.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Checksum OK (${SUMS_FILE}).${NC}"
else
    echo -e "${ORANGE}No checksum file found for this release, the download cannot be verified.${NC}"
    confirm_risky "Continue without verification?" || exit 1
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
    if [ -e "$old" ]; then
        cp -p "$old" "$BACKUP_DIR/"
    fi
done

echo -e "${CYAN}Installing...${NC}"
if ! install -m 0755 -o root -g root -t "$BIN_DIR" "syscoin-${VER}/bin/"*; then
    echo -e "${RED}Install failed.${NC}"
    rollback || true
    start_node || echo -e "${RED}Failed to restart syscoind.${NC}"
    exit 1
fi

# Sentinel cleanup (Sentinel is no longer used since Syscoin 4)
rm -rf /root/sentinel
if current_crontab=$(crontab -l 2> /dev/null) && grep -q sentinel <<< "$current_crontab"; then
    echo -e "${CYAN}Disabling old Sentinel cron job...${NC}"
    sed '/sentinel/s/^\([^#]\)/#\1/' <<< "$current_crontab" | crontab -
fi

# Ask the user what to do next, unless --action was given
if [ -z "$ACTION" ]; then
    if [ "$ASSUME_YES" -eq 1 ]; then
        ACTION="start"
    else
        echo -e "${GREEN}Choose an action before restarting SyscoinCore:${NC}"
        echo "1) Start SyscoinCore normally (default, recommended)"
        echo "2) Start with reindex (recommended for data integrity issues)"
        echo "3) Clean ~/.syscoin (keeps syscoin.conf and wallets) and reboot"
        echo "4) Cancel (SyscoinCore stays STOPPED, masternode will be offline!)"
        user_choice=""
        read -rp "Enter your choice [1-4, default 1]: " user_choice || true
        case "${user_choice:-1}" in
            1) ACTION="start" ;;
            2) ACTION="reindex" ;;
            3) ACTION="clean" ;;
            4) ACTION="cancel" ;;
            *)
                echo -e "${RED}Invalid choice. SyscoinCore is NOT running, start it with: syscoind -daemon${NC}"
                exit 1
                ;;
        esac
    fi
fi

case "$ACTION" in
    start)
        echo -e "${CYAN}Starting Syscoincore...${NC}"
        ;;
    reindex)
        echo -e "${CYAN}Starting Syscoincore with reindex...${NC}"
        START_ARGS=(-reindex)
        ;;
    clean)
        if [ ! -d "$DATA_DIR" ]; then
            echo -e "${RED}${DATA_DIR} not found. Exiting.${NC}"
            exit 1
        fi
        echo -e "${RED}This deletes all blockchain data in ${DATA_DIR} (syscoin.conf, wallet.dat and wallets/ are kept).${NC}"
        really=""
        if [ "$ASSUME_YES" -eq 1 ]; then
            really="YES"
        else
            read -rp "Type YES to continue: " really || true
        fi
        if [ "$really" != "YES" ]; then
            echo -e "${ORANGE}Cleanup cancelled, starting SyscoinCore normally.${NC}"
        else
            echo -e "${ORANGE}Cleaning ${DATA_DIR}...${NC}"
            find "$DATA_DIR" -mindepth 1 -maxdepth 1 \
                ! -name 'syscoin.conf' ! -name 'wallet.dat' ! -name 'wallets' \
                -exec rm -rf {} +
            echo -e "${GREEN}Cleanup complete. Previous binaries are backed up in ${BACKUP_DIR}. Rebooting system...${NC}"
            sleep 3
            reboot
            exit 0
        fi
        ;;
    cancel)
        echo -e "${RED}Cancelled by user. SyscoinCore is NOT running, start it with: syscoind -daemon${NC}"
        exit 0
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
syscoin-cli -version || echo -e "${RED}Failed to check Syscoin version.${NC}"

echo -e "${CYAN}Waiting for RPC to become available...${NC}"

if blocks=$(timeout 300 syscoin-cli -rpcwait getblockcount); then
    echo -e "${CYAN}Current block height: ${ORANGE}${blocks}${NC}"
    echo -e "${CYAN}Masternode status:${ORANGE}"
    syscoin-cli masternode status || echo -e "${RED}Could not fetch masternode status.${NC}"
else
    echo -e "${RED}RPC did not become available within 5 minutes, check debug.log.${NC}"
fi

echo -e "${GREEN}Done. Previous binaries are backed up in ${BACKUP_DIR}${NC}"
echo -e "${CYAN}Liked it? Syscoin Tippingjar: ${ORANGE}sys1qpqnzpdg4thlktvzgkpazzh3yduh8ctum2eguxe${NC}"
echo -e "${PURPLE}Thanks!${NC}"
