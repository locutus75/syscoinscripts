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
  -n, --no-animation    Disable the spinning coin and spinners
  -h, --help            Show this help

Example for cron/automation: $0 --yes --action start
EOF
}

# Parse arguments
ACTION=""
ASSUME_YES=0
FORCE=0
UPGRADE_SYSTEM=0
NO_ANIMATION=0
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
        -n|--no-animation)   NO_ANIMATION=1 ;;
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

# ---------------------------------------------------------------------------
# Console animations: spinning Syscoin coin and spinners.
# Only used on a UTF-8 terminal; disabled with --no-animation or when output
# is redirected (cron, logs), then plain text is printed instead.
# ---------------------------------------------------------------------------
ANIMATE=0
if [ "$NO_ANIMATION" -eq 0 ] && [ -t 1 ] && [ -t 2 ] && [ "${TERM:-dumb}" != "dumb" ] \
    && [ "$(locale charmap 2> /dev/null || true)" = "UTF-8" ] && command -v awk > /dev/null; then
    ANIMATE=1
fi

WORK_DIR=""
cleanup() {
    if [ -n "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
    if [ "$ANIMATE" -eq 1 ]; then
        printf '\033[0m\033[?25h' # reset colors, show cursor
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# awk program that renders the animation frames with half-block characters
# (2 square pixels per character cell): a spinning coin with a white "S" in
# front of a twinkling grid of grey squares that fades out towards the top.
# Input variables: D = coin diameter (pixels), N = frames per rotation,
# ROUNDS = rotations, BW = width in columns, T1/T2 = text lines.
# Output: ROUNDS*N spinning frames plus one final face-on frame, each
# D/2+2 lines long.
read -r -d '' COIN_AWK <<'AWK' || true
function abs(x) { return x < 0 ? -x : x }
# True when face-on point (x,y) lies on the "S": two arcs stacked on top of each other
function on_s(x, y,   d, t) {
    d = sqrt(x * x + (y + SR) ^ 2)                        # upper arc, centre (0,-SR)
    if (abs(d - SR) <= SW) {
        t = atan2(y + SR, x) * 180 / PI
        if (t >= 90 || t <= -35) return 1
    }
    d = sqrt(x * x + (y - SR) ^ 2)                        # lower arc, centre (0,SR)
    if (abs(d - SR) <= SW) {
        t = atan2(y - SR, x) * 180 / PI
        if (t >= -90 && t <= 145) return 1
    }
    return 0
}
# Colour of coin pixel (u,v), both in [-1,1], for the current angle; 0 = transparent.
# The coin turns around its vertical axis: the face towards the viewer is shifted
# by half the thickness, so the edge shows on one side only. After a half turn the
# back is visible, where the "S" is seen mirrored.
function coin(u, v,   half, xf, up, r2) {
    if (v * v > 1) return 0
    half = sqrt(1 - v * v)
    xf = (cs > 0 ? 1 : -1) * T / 2 * sn                   # centre of the visible face
    if (ac > 0.04 && ((u - xf) / cs) ^ 2 + v * v <= 1) {
        up = (u - xf) / cs                                # face-on x, mirrored on the back
        r2 = up * up + v * v
        if (r2 > 0.80) return rim
        if (on_s(up, v)) return SYM
        return shade
    }
    if (abs(u) <= ac * half + T / 2 * abs(sn)) return EDGE
    return 0
}
# Random grey level for a background square in pixel row y: dark at the top,
# fading in, with a few bright squares
function level(y,   f) {
    f = y / (PH * 0.5); if (f > 1) f = 1; f = f * f
    if (rand() < 0.07 * f) return 250 - int(rand() * 5)
    return 233 + int(f * (3 + rand() * rand() * 13))
}
# Colour of pixel (x,y) of the whole picture
function pixel(x, y,   c, cx) {
    cx = x - CX
    if (cx >= 0 && cx < D && y >= CY && y < CY + D) {
        c = coin((cx + 0.5) / D * 2 - 1, (y - CY + 0.5) / D * 2 - 1)
        if (c) return c
    }
    if (x % 2 || y % 2) return GAP                        # dark seams between the squares
    return L[x, y]
}
# Print one character cell with top/bottom pixel colours, only sending colour codes that change
function cell(t, b,   codes) {
    codes = ""
    if (t == b) {
        if (b != curbg) { codes = "48;5;" b; curbg = b }
        out = out (codes != "" ? "\033[" codes "m" : "") " "
        return
    }
    if (t != curfg) { codes = "38;5;" t; curfg = t }
    if (b != curbg) { codes = codes (codes != "" ? ";" : "") "48;5;" b; curbg = b }
    out = out (codes != "" ? "\033[" codes "m" : "") "▀"
}
function visible_len(s) { gsub(/\033\[[0-9;]*m/, "", s); return length(s) }
function frame(a,   x, y, row, txt, tx) {
    cs = cos(a); sn = sin(a); ac = abs(cs)
    # darker as the coin turns away, back side slightly darker than the front
    shade = ac > 0.75 ? 27 : (ac > 0.45 ? 26 : 25)
    rim   = ac > 0.75 ? 39 : (ac > 0.45 ? 33 : 32)
    if (cs < 0) { shade = ac > 0.75 ? 26 : 25; rim = ac > 0.75 ? 33 : 32 }
    for (row = 0; row < ROWS; row++) {
        out = ""; curfg = -1; curbg = -1
        txt = (row == TR1) ? T1 : ((row == TR2) ? T2 : "")
        for (x = 0; x < BW; x++) {
            # text panel: dark box to the right of the coin
            if (row >= TR1 - 1 && row <= TR2 + 1 && x >= TX && x < TX + TW) {
                if (x == TX + 2 && txt != "") {
                    out = out "\033[0m\033[48;5;" PANEL "m" txt "\033[0m\033[48;5;" PANEL "m"
                    curfg = -1; curbg = PANEL
                    x += visible_len(txt) - 1
                    continue
                }
                cell(PANEL, PANEL)
                continue
            }
            cell(pixel(x, 2 * row), pixel(x, 2 * row + 1))
        }
        print out "\033[0m"
    }
}
BEGIN {
    srand()
    PI = atan2(0, -1)
    T = 0.16; SR = 0.30; SW = 0.12                        # T = coin thickness
    EDGE = 24; SYM = 231; GAP = 232; PANEL = 16
    ROWS = D / 2 + 2; PH = 2 * ROWS
    CX = 2; CY = 2                                        # coin position in pixels
    TX = CX + D + 3; TW = BW - TX - 1                     # text panel columns
    if (TW > 46) TW = 46
    TR1 = int(ROWS / 2) - 2; TR2 = TR1 + 2                # text rows
    # keep the panel background when the text resets its colours
    gsub(/\033\[0m/, "\033[0m\033[48;5;" PANEL "m", T1)
    gsub(/\033\[0m/, "\033[0m\033[48;5;" PANEL "m", T2)
    for (y = 0; y < PH; y += 2) for (x = 0; x < BW; x += 2) L[x, y] = level(y)
    for (f = 0; f <= ROUNDS * N; f++) {
        frame(2 * PI * (f % N) / N)
        # let some squares twinkle
        for (y = 0; y < PH; y += 2) for (x = 0; x < BW; x += 2) if (rand() < 0.08) L[x, y] = level(y)
    }
}
AWK

COIN_SIZE=32
COIN_FRAMES=24
COIN_ROWS=$((COIN_SIZE / 2 + 2))

# Show the spinning coin in front of the twinkling background for a number of
# rotations, ending face-on with two lines of text next to it.
# Any key skips the animation.
show_coin() {
    local rounds="$1" text1="$2" text2="$3"
    local cols lines width k total key=""
    local -a frames=()

    if [ "$ANIMATE" -eq 1 ]; then
        read -r lines cols < <(stty size < /dev/tty 2> /dev/null || echo 24 80)
        if [ "$cols" -ge 80 ] && [ "$lines" -ge $((COIN_ROWS + 4)) ]; then
            width=$((cols > 120 ? 120 : cols))
            mapfile -t frames < <(awk -v D="$COIN_SIZE" -v N="$COIN_FRAMES" -v ROUNDS="$rounds" \
                -v BW="$width" -v T1="$text1" -v T2="$text2" "$COIN_AWK")
        fi
    fi
    total=$((rounds * COIN_FRAMES + 1))
    if [ "${#frames[@]}" -ne $((total * COIN_ROWS)) ]; then
        echo -e "${text1}"
        echo -e "${text2}"
        return 0
    fi

    printf '\033[?25l'
    for ((k = 0; k < total - 1; k++)); do
        printf '%s\n' "${frames[@]:k*COIN_ROWS:COIN_ROWS}"
        printf '\033[%dA' "$COIN_ROWS"
        if [ -t 0 ]; then
            if read -rsn1 -t 0.05 key 2> /dev/null; then
                break
            fi
        else
            sleep 0.05
        fi
    done
    # Final frame: coin facing forward
    printf '%s\n' "${frames[@]:(total-1)*COIN_ROWS:COIN_ROWS}"
    printf '\033[?25h'
    echo
}

# Mini coin spinner frames
SPIN=()
for _s in "(S)" "(S)" "|S|" " | " "|S|" "(S)"; do
    SPIN+=("\033[38;5;33m${_s:0:1}\033[1;97m${_s:1:1}\033[0;38;5;33m${_s:2:1}\033[0m")
done

spin_frame() { # message, frame counter, start time
    printf '\r\033[K %b %b%s %b(%ds)%b' "${SPIN[$(($2 / 2 % ${#SPIN[@]}))]}" "$CYAN" "$1" "$NC" $((SECONDS - $3)) "$NC" >&2
}

spin_done() { # exit code, message, start time
    if [ "$1" -eq 0 ]; then
        printf '\r\033[K %b✔%b %s (%ds)\n' "$GREEN" "$NC" "$2" $((SECONDS - $3)) >&2
    else
        printf '\r\033[K %b✘%b %s (%ds)\n' "$RED" "$NC" "$2" $((SECONDS - $3)) >&2
    fi
    printf '\033[?25h' >&2
}

# Run a command with a spinner. Its stdout is passed through after it finishes,
# so it can be used in $(...). Returns the exit code of the command.
spin_run() {
    local msg="$1" start=$SECONDS i=0 rc=0 pid out
    shift
    if [ "$ANIMATE" -eq 0 ]; then
        echo -e "${CYAN}${msg}...${NC}" >&2
        "$@"
        return
    fi
    out=$(mktemp)
    "$@" > "$out" 2> "$out.err" < /dev/null &
    pid=$!
    printf '\033[?25l' >&2
    while kill -0 "$pid" 2> /dev/null; do
        spin_frame "$msg" "$i" "$start"
        i=$((i + 1))
        sleep 0.1
    done
    wait "$pid" || rc=$?
    spin_done "$rc" "$msg" "$start"
    cat "$out"
    if [ "$rc" -ne 0 ]; then
        cat "$out.err" >&2
    fi
    rm -f "$out" "$out.err"
    return "$rc"
}

# Wait with a spinner until a command succeeds, max <timeout> seconds.
spin_until() {
    local timeout="$1" msg="$2" start=$SECONDS i=0
    shift 2
    if [ "$ANIMATE" -eq 0 ]; then
        echo -e "${CYAN}${msg} (max ${timeout}s)...${NC}"
        while [ $((SECONDS - start)) -lt "$timeout" ]; do
            "$@" && return 0
            sleep 1
        done
        return 1
    fi
    printf '\033[?25l' >&2
    while [ $((SECONDS - start)) -lt "$timeout" ]; do
        if [ $((i % 5)) -eq 0 ] && "$@"; then
            spin_done 0 "$msg" "$start"
            return 0
        fi
        spin_frame "$msg" "$i" "$start"
        i=$((i + 1))
        sleep 0.1
    done
    spin_done 1 "$msg" "$start"
    return 1
}

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script as root, e.g.: sudo $0${NC}"
    exit 1
fi

show_coin 2 "${CYAN}\033[1mS Y S C O I N${NC}" "${PURPLE}Masternode updater${NC}"

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

node_stopped() {
    ! pgrep -x syscoind > /dev/null
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

    spin_until 300 "Waiting for syscoind to shut down" node_stopped
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
    spin_run "Checking that syscoind keeps running" sleep 10
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
    if ! { spin_run "Updating package lists" apt-get -y update > /dev/null \
        && spin_run "Upgrading system packages" env DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null; }; then
        echo -e "${ORANGE}Package upgrade failed, continuing with the Syscoin update.${NC}"
    fi
fi

echo -e "${PURPLE}Updating Syscoin Masternode to version ${VER}${NC}"

# Download and verify before stopping the node, to keep downtime minimal
WORK_DIR=$(mktemp -d)
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

if ! spin_run "Unpacking" tar xf "$TARBALL"; then
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

if blocks=$(spin_run "Waiting for RPC to become available" timeout 300 syscoin-cli -rpcwait getblockcount); then
    echo -e "${CYAN}Current block height: ${ORANGE}${blocks}${NC}"
    echo -e "${CYAN}Masternode status:${ORANGE}"
    syscoin-cli masternode status || echo -e "${RED}Could not fetch masternode status.${NC}"
else
    echo -e "${RED}RPC did not become available within 5 minutes, check debug.log.${NC}"
fi

echo
show_coin 1 "${GREEN}\033[1mDone!${NC} Syscoin ${VER} is running." "${PURPLE}Thanks for running a Syscoin masternode!${NC}"
echo -e "${CYAN}Previous binaries are backed up in ${BACKUP_DIR}${NC}"
echo -e "${CYAN}Liked it? Syscoin Tippingjar: ${ORANGE}sys1qpqnzpdg4thlktvzgkpazzh3yduh8ctum2eguxe${NC}"
echo -e "${PURPLE}Thanks!${NC}"
