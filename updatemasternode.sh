#!/bin/bash
set -euo pipefail

# Set up color variables (cleared later when the output is not a terminal)
GREEN='\033[1;32m'
RED='\033[1;31m'
ORANGE='\033[1;33m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
BLUE='\033[1;38;5;33m'
BOLD='\033[1m'
DIM='\033[2m'
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
  -t, --truecolor       Use 24-bit colours for the coin (auto-detected via COLORTERM)
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
TRUECOLOR=0
case "${COLORTERM:-}" in truecolor|24bit) TRUECOLOR=1 ;; esac
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
        -t|--truecolor)      TRUECOLOR=1 ;;
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

# No colours when the output goes to a file/cron log, or when NO_COLOR is set
if [ ! -t 1 ] || [ -n "${NO_COLOR:-}" ]; then
    GREEN="" RED="" ORANGE="" PURPLE="" CYAN="" BLUE="" BOLD="" DIM="" NC=""
fi

# ---------------------------------------------------------------------------
# Output helpers: numbered steps with a header line, and indented status lines
# with a symbol in front. ASCII symbols when the locale is not UTF-8.
# ---------------------------------------------------------------------------
if [ "$(locale charmap 2> /dev/null || true)" = "UTF-8" ]; then
    I_OK="✔" I_FAIL="✘" I_WARN="!" I_INFO="›" I_ASK="?" LINE="─"
    BOX_TL="╭" BOX_TR="╮" BOX_BL="╰" BOX_BR="╯" BOX_V="│"
else
    I_OK="+" I_FAIL="x" I_WARN="!" I_INFO=">" I_ASK="?" LINE="-"
    BOX_TL="+" BOX_TR="+" BOX_BL="+" BOX_BR="+" BOX_V="|"
fi
STEP=0
STEPS=7

repeat() { # string, count
    local out=""
    printf -v out '%*s' "$2" ''
    printf '%s' "${out// /$1}"
}

step() { # title
    local title
    STEP=$((STEP + 1))
    title=" [${STEP}/${STEPS}] $1 "
    echo
    echo -e "${BLUE}$(repeat "$LINE" 2)${NC}${BOLD}${title}${NC}${BLUE}$(repeat "$LINE" $((60 - ${#title})))${NC}"
}

info() { echo -e "   ${DIM}${I_INFO}${NC} $*"; }
ok()   { echo -e "   ${GREEN}${I_OK}${NC} $*"; }
warn() { echo -e "   ${ORANGE}${I_WARN} $*${NC}"; }
fail() { echo -e "   ${RED}${I_FAIL} $*${NC}"; }
kv()   { printf "   ${DIM}%-16s${NC} %b\n" "$1" "$2"; }

# Length of a string without colour codes
visible_len() {
    local plain
    plain=$(printf '%b' "$1" | sed 's/\x1b\[[0-9;]*m//g')
    echo "${#plain}"
}

# Box with a title and "label=value" rows
summary_box() { # title, rows...
    local title="$1" row label value width=0 len line
    local -a lines=()
    shift
    local maxw=74 cols
    if [ -t 1 ]; then
        cols=$(stty size < /dev/tty 2> /dev/null | cut -d' ' -f2 || true)
        if [ -n "$cols" ] && [ "$cols" -gt 30 ]; then
            maxw=$((cols - 6))
        fi
    fi
    for row in "$@"; do
        label="${row%%=*}"
        value="${row#*=}"
        if [ "$(visible_len "$value")" -gt $((maxw - 15)) ] && [[ "$value" != *$'\033'* ]] && [[ "$value" != *'\033'* ]]; then
            value="...${value: -$((maxw - 18))}"
        fi
        line="$(printf '%-14s' "$label") ${value}"
        lines+=("$line")
        len=$(visible_len "$line")
        if [ "$len" -gt "$width" ]; then
            width=$len
        fi
    done
    if [ "$width" -lt $((${#title} + 4)) ]; then
        width=$((${#title} + 4))
    fi
    echo
    echo -e "${BLUE}${BOX_TL}${LINE} ${NC}${BOLD}${title}${NC}${BLUE} $(repeat "$LINE" $((width - ${#title} + 1)))${BOX_TR}${NC}"
    for line in "${lines[@]}"; do
        len=$(visible_len "$line")
        echo -e "${BLUE}${BOX_V}${NC}  ${line}$(repeat " " $((width - len)))  ${BLUE}${BOX_V}${NC}"
    done
    echo -e "${BLUE}${BOX_BL}$(repeat "$LINE" $((width + 4)))${BOX_BR}${NC}"
}

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
# (2 square pixels per character cell): a spinning 16-bit style pixel-art coin in
# the colours of the Syscoin logo (white face with the blue "S", dark inner ring,
# blue rim, dithered shading, sparkle) in front of a twinkling grid of grey
# squares that fades out towards the top. The "S" is an embedded coverage mask of
# the logo.
# Input variables: D = coin diameter (pixels), N = frames per rotation,
# ROUNDS = rotations, BW = width in columns, T1/T2 = text lines,
# TC = 1 for truecolor (24-bit), 0 for the 256-colour fallback.
# Output: ROUNDS*N spinning frames plus one final face-on frame, each
# D/2+2 lines long.
read -r -d '' COIN_AWK <<'AWK' || true
function abs(x) { return x < 0 ? -x : x }
function clamp(x) { return x < 0 ? 0 : (x > 1 ? 1 : x) }
# Colours are handled as "r;g;b" strings
function rgb(r, g, b) { return int(clamp(r / 255) * 255 + 0.5) ";" int(clamp(g / 255) * 255 + 0.5) ";" int(clamp(b / 255) * 255 + 0.5) }
function hex(h) { return rgb(H2D[substr(h, 1, 2)], H2D[substr(h, 3, 2)], H2D[substr(h, 5, 2)]) }
# Coverage (0..1) of the Syscoin "S" at face-on point (x,y), with (x,y) scaled so
# that the white face has radius 1. Bilinear interpolation of the logo mask.
function s_cover(x, y,   fx, fy, ix, iy, dx, dy) {
    fx = (x + 1) / 2 * SN - 0.5; fy = (y + 1) / 2 * SN - 0.5
    ix = int(fx); iy = int(fy)
    if (fx < 0 || fy < 0 || ix >= SN - 1 || iy >= SN - 1) return 0
    dx = fx - ix; dy = fy - iy
    return ((SM[iy, ix] * (1 - dx) + SM[iy, ix + 1] * dx) * (1 - dy) \
        + (SM[iy + 1, ix] * (1 - dx) + SM[iy + 1, ix + 1] * dx) * dy) / 9
}
# Pixel-art colour of the coin face at face-on point (x,y): flat palette colours,
# hard edges and checkerboard dithering instead of gradients. White face with the
# blue "S", dark inner ring and a blue rim with a highlight, like the Syscoin logo.
# LX/LY = logical pixel (for the dither pattern), SHADE shifts the shading when the
# coin turns away or shows its back.
function face(x, y,   r, t, dith) {
    r = sqrt(x * x + y * y)
    t = x * 0.6 + y * 0.8 + SHADE                          # light from the top left
    dith = (LX + LY) % 2
    if (r > RIM_R) {
        if (t < -0.55) return RIM_HI
        if (t > 0.55) return RIM_LO
        return RIM
    }
    if (r > RING_R) return RING
    if (s_cover(x / RING_R, y / RING_R) >= 0.5) {          # the "S" in three flat bands
        if (y < -0.4) return (y < -0.5 || dith) ? S_HI : S_MID
        if (y > 0.45) return (y > 0.55 || dith) ? S_LO : S_MID
        return S_MID
    }
    if (t > 0.75) return FACE_LO                          # shaded part of the face
    if (t > 0.45) return dith ? FACE_LO : FACE_HI         # dithered transition
    return FACE_HI
}
# Colour of coin pixel (u,v), both in [-1,1], for the current angle; "" = transparent.
# The coin turns around its vertical axis: the face towards the viewer is shifted
# by half the thickness, so the edge shows on one side only. After a half turn the
# back is visible, where the "S" is seen mirrored.
function coin(u, v,   half, xf) {
    if (v * v > 1) return ""
    half = sqrt(1 - v * v)
    xf = (cs > 0 ? 1 : -1) * T / 2 * sn                   # centre of the visible face
    if (ac > 0.15 && ((u - xf) / cs) ^ 2 + v * v <= 1)
        return face((u - xf) / cs, v)                     # face-on x, mirrored on the back
    if (abs(u) <= ac * half + T / 2 * abs(sn))            # striped edge
        return LY % 2 ? EDGE_LO : EDGE_HI
    return ""
}
# Render the coin for the current angle on the sprite pixel grid, and add a
# sparkle on the frames around face-on.
function render_coin(f,   lx, ly, c, sx, sy, big) {
    delete CL
    for (ly = 0; ly < DL; ly++) for (lx = 0; lx < DL; lx++) {
        LX = lx; LY = ly
        c = coin((lx + 0.5) / DL * 2 - 1, (ly + 0.5) / DL * 2 - 1)
        if (c != "") CL[lx, ly] = c
    }
    f = f % N
    if (f == 0 || f == 1 || f == N - 1) {
        big = (f == 0)
        sx = DL - 1; sy = 0                               # top right, just outside the coin
        CL[sx, sy] = SPARK
        CL[sx - 1, sy] = CL[sx + 1, sy] = CL[sx, sy - 1] = CL[sx, sy + 1] = big ? SPARK : SPARK2
        if (big) CL[sx - 2, sy] = CL[sx + 2, sy] = CL[sx, sy - 2] = CL[sx, sy + 2] = SPARK2
    }
}
# Random grey level for a background square in pixel row y: dark at the top,
# fading in, with a few bright squares
function level(y,   f, g) {
    f = y / (PH * 0.5); if (f > 1) f = 1; f = f * f
    if (rand() < 0.07 * f) g = 188 + int(rand() * 50)
    else g = 18 + int(f * (30 + rand() * rand() * 130))
    return rgb(g, g, g)
}
# Colour of pixel (x,y) of the whole picture
function pixel(x, y,   lx, ly) {
    lx = int((x - CX + PX * 3) / PX) - 3; ly = int((y - CY + PX * 3) / PX) - 3
    if ((lx, ly) in CL) return CL[lx, ly]
    return (x % 2 || y % 2) ? GAP : L[x, y]               # dark seams between the squares
}
# 256-colour index for "r;g;b" (for terminals without truecolor): greys map to the
# grey ramp, other colours to the nearest of a fixed set of blues so the coin
# keeps a consistent colour
function to256(c,   p, i, q, d, best, bd, gi) {
    if (c in C256) return C256[c]
    split(c, p, ";")
    if (p[1] == p[2] && p[2] == p[3]) {
        gi = int((p[1] - 8) / 10 + 0.5); if (gi < 0) gi = 0; if (gi > 23) gi = 23
        return C256[c] = (p[1] < 4 ? 16 : 232 + gi)
    }
    bd = -1
    for (i = 1; i <= NPAL; i++) {
        split(PALRGB[i], q, ";")
        d = (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 + (p[3] - q[3]) ^ 2
        if (bd < 0 || d < bd) { bd = d; best = PAL[i] }
    }
    return C256[c] = best
}
function sgr(kind, c) { return TC ? kind "8;2;" c : kind "8;5;" to256(c) }
# Print one character cell with top/bottom pixel colours, only sending colour codes that change
function cell(t, b,   codes) {
    codes = ""
    if (t == b) {
        if (b != curbg) { codes = sgr(4, b); curbg = b }
        out = out (codes != "" ? "\033[" codes "m" : "") " "
        return
    }
    if (t != curfg) { codes = sgr(3, t); curfg = t }
    if (b != curbg) { codes = codes (codes != "" ? ";" : "") sgr(4, b); curbg = b }
    out = out (codes != "" ? "\033[" codes "m" : "") "▀"
}
function visible_len(s) { gsub(/\033\[[0-9;]*m/, "", s); return length(s) }
# Set the rotation angle for the next frame
function set_angle(a) {
    cs = cos(a); sn = sin(a); ac = abs(cs)
    SHADE = (1 - ac) * 0.6 + (cs < 0 ? 0.35 : 0)          # darker as the coin turns away, back a bit darker
}
function frame(   x, y, row, txt) {
    for (row = 0; row < ROWS; row++) {
        out = ""; curfg = ""; curbg = ""
        txt = (row == TR1) ? T1 : ((row == TR2) ? T2 : "")
        for (x = 0; x < BW; x++) {
            # text panel: dark box to the right of the coin
            if (row >= TR1 - 1 && row <= TR2 + 1 && x >= TX && x < TX + TW) {
                if (x == TX + 2 && txt != "") {
                    out = out "\033[0m\033[" sgr(4, PANEL) "m" txt "\033[0m\033[" sgr(4, PANEL) "m"
                    curfg = ""; curbg = PANEL
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
    for (i = 0; i < 256; i++) H2D[sprintf("%02x", i)] = i
    # 256-colour fallback palette: blues from navy to light blue, light greys for the face, dark greys
    NPAL = split("16 17 18 19 20 21 25 26 27 32 33 39 68 69 75 111 153 231 255 254 253 252 250 247 233 235 237", PAL, " ")
    split("000000 00005f 000087 0000af 0000d7 0000ff 005faf 005fd7 005fff 0087d7 0087ff 00afff 5f87d7 5f87ff 5fafff 87afff afd7ff ffffff eeeeee e4e4e4 dadada d0d0d0 bcbcbc 9e9e9e 121212 262626 3a3a3a", PH6, " ")
    for (i = 1; i <= NPAL; i++) PALRGB[i] = hex(PH6[i])
    # pixel-art palette in the colours of the Syscoin logo (all exact xterm-256 colours,
    # so truecolor and 256-colour terminals look the same)
    FACE_HI = hex("eeeeee"); FACE_LO = hex("bcbcbc"); RING = hex("262626")
    S_HI = hex("5fafff"); S_MID = hex("0087ff"); S_LO = hex("005fd7")
    RIM_HI = hex("5f87ff"); RIM = hex("005fff"); RIM_LO = hex("0000af")
    EDGE_HI = hex("005fd7"); EDGE_LO = hex("0000af"); SPARK = hex("ffffff"); SPARK2 = hex("5fafff")
    GAP = hex("0b0b0f"); PANEL = hex("000000")
    T = 0.20                                              # coin thickness
    PX = PX ? PX : 1; DL = int(D / PX)                    # size of one sprite pixel, sprite size
    RING_R = 0.83; RIM_R = 0.90                           # radius of the dark ring and the blue rim
    # Syscoin "S" logo mask: coverage 0-9 per cell, SN x SN cells over the white face
    S_MASK = S_MASK "000000000000000000000000000000000000000000000000"
    S_MASK = S_MASK "000000000000000000000000000000000000000000000000"
    S_MASK = S_MASK "000000000000000000000000000000000000000000000000"
    S_MASK = S_MASK "000000000000000000000000000000000000000000000000"
    S_MASK = S_MASK "000000000000000000000000000000000000000000000000"
    S_MASK = S_MASK "000000000000000000000112222210000000000000000000"
    S_MASK = S_MASK "000000000000000001468999999998641000000000000000"
    S_MASK = S_MASK "000000000000001479999999999999999741000000000000"
    S_MASK = S_MASK "000000000000048999999999988778899998400000000000"
    S_MASK = S_MASK "000000000003899999999642000000001246882000000000"
    S_MASK = S_MASK "000000000049999999841000000000000000014300000000"
    S_MASK = S_MASK "000000000699999995100000000000000000000000000000"
    S_MASK = S_MASK "000000006999999940000000000000000000000000000000"
    S_MASK = S_MASK "000000059999999500000000000000000000000000000000"
    S_MASK = S_MASK "000000299999998000000000002221000000000000000000"
    S_MASK = S_MASK "000000799999995000000000489999964100000000000000"
    S_MASK = S_MASK "000003999999992000000003999999999962000000000000"
    S_MASK = S_MASK "000005999999991000000006999999999999610000000000"
    S_MASK = S_MASK "000008999999992000000005999999999999993000000000"
    S_MASK = S_MASK "000019999999994000000001899999999999999500000000"
    S_MASK = S_MASK "000019999999997000000000179999999999999950000000"
    S_MASK = S_MASK "000019999999999300000000005999999999999992000000"
    S_MASK = S_MASK "000009999999999910000000000159999999999998000000"
    S_MASK = S_MASK "000006999999999981000000000003999999999999300000"
    S_MASK = S_MASK "000004999999999998300000000000189999999999600000"
    S_MASK = S_MASK "000000899999999999951000000000029999999999900000"
    S_MASK = S_MASK "000000399999999999999400000000003999999999910000"
    S_MASK = S_MASK "000000059999999999999971000000000799999999910000"
    S_MASK = S_MASK "000000005999999999999998100000000499999999910000"
    S_MASK = S_MASK "000000000499999999999999500000000299999999800000"
    S_MASK = S_MASK "000000000017999999999999700000000199999999600000"
    S_MASK = S_MASK "000000000000269999999999400000000299999999300000"
    S_MASK = S_MASK "000000000000001479999984000000000599999998000000"
    S_MASK = S_MASK "000000000000000000222200000000000899999993000000"
    S_MASK = S_MASK "000000000000000000000000000000005999999960000000"
    S_MASK = S_MASK "000000000000000000000000000000049999999700000000"
    S_MASK = S_MASK "000000000000000000000000000001699999996000000000"
    S_MASK = S_MASK "000000003410000000000000000159999999950000000000"
    S_MASK = S_MASK "000000000388642100000000247999999998300000000000"
    S_MASK = S_MASK "000000000004999998877889999999999950000000000000"
    S_MASK = S_MASK "000000000000157999999999999999974100000000000000"
    S_MASK = S_MASK "000000000000000146899999999864100000000000000000"
    S_MASK = S_MASK "000000000000000000012333221000000000000000000000"
    S_MASK = S_MASK "000000000000000000000000000000000000000000000000"
    S_MASK = S_MASK "000000000000000000000000000000000000000000000000"
    S_MASK = S_MASK "000000000000000000000000000000000000000000000000"
    S_MASK = S_MASK "000000000000000000000000000000000000000000000000"
    S_MASK = S_MASK "000000000000000000000000000000000000000000000000"
    SN = 48
    for (i = 0; i < SN * SN; i++) SM[int(i / SN), i % SN] = substr(S_MASK, i + 1, 1) + 0
    ROWS = D / 2 + 2; PH = 2 * ROWS
    CX = 2; CY = 2                                        # coin position in pixels
    TX = CX + D + 3; TW = BW - TX - 1                     # text panel columns
    if (TW > 46) TW = 46
    TR1 = int(ROWS / 2) - 2; TR2 = TR1 + 2                # text rows
    # keep the panel background when the text resets its colours
    gsub(/\033\[0m/, "\033[0m\033[" sgr(4, PANEL) "m", T1)
    gsub(/\033\[0m/, "\033[0m\033[" sgr(4, PANEL) "m", T2)
    for (y = 0; y < PH; y += 2) for (x = 0; x < BW; x += 2) L[x, y] = level(y)
    for (f = 0; f <= ROUNDS * N; f++) {
        set_angle(2 * PI * (f % N) / N)
        render_coin(f)
        frame()
        # let some squares twinkle
        for (y = 0; y < PH; y += 2) for (x = 0; x < BW; x += 2) if (rand() < 0.08) L[x, y] = level(y)
    }
}
AWK

COIN_SIZE=32
COIN_FRAMES=8                     # frames per rotation, stepped like a console sprite
COIN_DELAY=0.09                   # seconds per frame
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
                -v BW="$width" -v TC="$TRUECOLOR" -v T1="$text1" -v T2="$text2" "$COIN_AWK")
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
            if read -rsn1 -t "$COIN_DELAY" key 2> /dev/null; then
                break
            fi
        else
            sleep "$COIN_DELAY"
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
    printf '\r\033[K   %b %s %b%ds%b' "${SPIN[$(($2 / 2 % ${#SPIN[@]}))]}" "$1" "$DIM" $((SECONDS - $3)) "$NC" >&2
}

spin_done() { # exit code, message, start time
    if [ "$1" -eq 0 ]; then
        printf '\r\033[K   %b%s%b %s %b%ds%b\n' "$GREEN" "$I_OK" "$NC" "$2" "$DIM" $((SECONDS - $3)) "$NC" >&2
    else
        printf '\r\033[K   %b%s %s%b %b%ds%b\n' "$RED" "$I_FAIL" "$2" "$NC" "$DIM" $((SECONDS - $3)) "$NC" >&2
    fi
    printf '\033[?25h' >&2
}

# Run a command with a spinner. Its stdout is passed through after it finishes,
# so it can be used in $(...). Returns the exit code of the command.
spin_run() {
    local msg="$1" start=$SECONDS i=0 rc=0 pid out
    shift
    if [ "$ANIMATE" -eq 0 ]; then
        info "${msg}..." >&2
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
        info "${msg} (max ${timeout}s)..."
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
    fail "Please run this script as root, e.g.: sudo $0"
    exit 1
fi

# Start on a clean screen (old output stays reachable in the scrollback)
if [ "$ANIMATE" -eq 1 ]; then
    printf '\033[H\033[2J'
fi
show_coin 3 "${CYAN}${BOLD}S Y S C O I N${NC}" "${PURPLE}Masternode updater${NC}"

BIN_DIR="/usr/local/bin"
DATA_DIR="$HOME/.syscoin"
BACKUP_DIR="$HOME/syscoin-backup-$(date +%F-%H%M%S)"
BACKUP_SHOW="${BACKUP_DIR/#$HOME/\~}"
SERVICE="syscoind"
USED_SYSTEMD=0
INSTALLED_VER=""
START_ARGS=()

# Ask a yes/no question, returns 0 on yes
confirm() {
    local answer=""
    if [ "$ASSUME_YES" -eq 1 ]; then
        info "$1 ${DIM}-> yes (--yes)${NC}"
        return 0
    fi
    printf '   %b%s%b %s %b[y/N]%b ' "$CYAN" "$I_ASK" "$NC" "$1" "$DIM" "$NC"
    read -r answer || true
    [ -t 0 ] || echo
    [[ "$answer" =~ ^[Yy]$ ]]
}

# Like confirm, but in non-interactive mode only yes when --force is given
confirm_risky() {
    if [ "$ASSUME_YES" -eq 1 ] && [ "$FORCE" -eq 0 ]; then
        info "$1 ${DIM}-> no (use --force to allow)${NC}"
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
        info "syscoind is managed by systemd (service ${SERVICE})"
        systemctl stop "$SERVICE" || warn "systemctl stop failed, checking if syscoind is running..."
    else
        syscoin-cli stop > /dev/null || warn "syscoin-cli stop failed, checking if syscoind is running..."
    fi

    spin_until 300 "Waiting for syscoind to shut down" node_stopped
}

# Start syscoind, extra arguments (e.g. -reindex) are passed to syscoind
start_node() {
    if [ "$USED_SYSTEMD" -eq 1 ] && [ $# -eq 0 ]; then
        systemctl start "$SERVICE" || return 1
    else
        if [ "$USED_SYSTEMD" -eq 1 ]; then
            warn "Starting syscoind manually with $*, the systemd service stays inactive until the next restart."
        fi
        syscoind -daemon "$@" > /dev/null || return 1
    fi

    # Make sure the process is still alive after startup
    spin_run "Checking that syscoind keeps running" sleep 10
    pgrep -x syscoind > /dev/null
}

# Restore the binaries from the backup directory
rollback() {
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR")" ]; then
        fail "No backup available to roll back to."
        return 1
    fi
    info "Restoring previous binaries from ${BACKUP_DIR}"
    install -m 0755 -o root -g root -t "$BIN_DIR" "$BACKUP_DIR"/*
}

# ---------------------------------------------------------------------------
step "Version check"

# Determine download architecture
case "$(uname -m)" in
    x86_64)         ARCH="x86_64-linux-gnu" ;;
    aarch64|arm64)  ARCH="aarch64-linux-gnu" ;;
    armv7l)         ARCH="arm-linux-gnueabihf" ;;
    *)
        fail "Unsupported architecture: $(uname -m)"
        exit 1
        ;;
esac

# Determine version: from argument, otherwise always the latest stable GitHub release
# (pre-releases such as testnet builds are skipped by GitHub's "latest")
VER_SOURCE="requested"
if [ -z "$VER" ]; then
    VER_SOURCE="latest release"
    # 1st try: redirect of /releases/latest (no API rate limit)
    latest_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/syscoin/syscoin/releases/latest" || true)
    VER=$(echo "$latest_url" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$' | cut -c2- || true)
    # 2nd try: GitHub API
    if [ -z "$VER" ]; then
        VER=$(curl -fsSL "https://api.github.com/repos/syscoin/syscoin/releases/latest" \
            | grep -oE '"tag_name": *"v[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
    fi
fi

if ! [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "Could not determine the latest version. Pass it manually, e.g.: $0 5.1.1"
    exit 1
fi

# Compare with installed version
INSTALLED_VER=$(syscoind -version 2> /dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)
kv "Architecture" "$ARCH"
kv "Installed" "${INSTALLED_VER:-${DIM}not found${NC}}"
kv "Target" "${BOLD}${VER}${NC} ${DIM}(${VER_SOURCE})${NC}"

if [ -n "$INSTALLED_VER" ]; then
    if [ "$INSTALLED_VER" = "$VER" ]; then
        if ! confirm_risky "Version ${VER} is already installed. Reinstall anyway?"; then
            ok "Already up to date, nothing to do."
            exit 0
        fi
    elif [ "$(printf '%s\n%s\n' "$INSTALLED_VER" "$VER" | sort -V | tail -n1)" = "$INSTALLED_VER" ]; then
        warn "${VER} is OLDER than the installed version ${INSTALLED_VER} (downgrade)."
        confirm_risky "Continue with downgrade?" || exit 0
    else
        ok "Update available: ${INSTALLED_VER} -> ${VER}"
    fi
fi

# ---------------------------------------------------------------------------
step "System packages"

# Optional OS package upgrade; a failure here does not abort the Syscoin update
if [ "$UPGRADE_SYSTEM" -eq 0 ] && [ "$ASSUME_YES" -eq 0 ]; then
    confirm "Also upgrade the system packages (apt-get upgrade)?" && UPGRADE_SYSTEM=1
fi
if [ "$UPGRADE_SYSTEM" -eq 1 ]; then
    if { spin_run "Updating package lists" apt-get -y update > /dev/null \
        && spin_run "Upgrading system packages" env DEBIAN_FRONTEND=noninteractive apt-get -y upgrade > /dev/null; }; then
        ok "System packages are up to date"
    else
        warn "Package upgrade failed, continuing with the Syscoin update."
    fi
else
    info "Skipped ${DIM}(use --upgrade-system to include)${NC}"
fi

# ---------------------------------------------------------------------------
step "Download"

# Download and verify before stopping the node, to keep downtime minimal
WORK_DIR=$(mktemp -d)
cd "$WORK_DIR" || { fail "Failed to change to work directory."; exit 1; }

TARBALL="syscoin-${VER}-${ARCH}.tar.gz"
BASE_URL="https://github.com/syscoin/syscoin/releases/download/v${VER}"

info "${TARBALL}"
if ! wget -q --show-progress "${BASE_URL}/${TARBALL}"; then
    fail "Download failed."
    exit 1
fi
ok "Downloaded $(du -h "$TARBALL" | cut -f1)"

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
        fail "${TARBALL} not listed in ${SUMS_FILE}."
        exit 1
    fi
    if ! sha256sum --quiet -c "${TARBALL}.sha256" > /dev/null 2>&1; then
        fail "Checksum verification FAILED, the download is not trusted."
        exit 1
    fi
    ok "Checksum verified ${DIM}(SHA256, ${SUMS_FILE})${NC}"
else
    warn "No checksum file found for this release, the download cannot be verified."
    confirm_risky "Continue without verification?" || exit 1
fi

if ! spin_run "Unpacking" tar xf "$TARBALL"; then
    fail "Extraction failed."
    exit 1
fi

if ! ls "syscoin-${VER}/bin/"* > /dev/null 2>&1; then
    fail "No binaries found in the archive."
    exit 1
fi

# ---------------------------------------------------------------------------
step "Stop SyscoinCore"

if ! stop_node; then
    fail "syscoind did not shut down in time. Exiting without changes."
    exit 1
fi

# ---------------------------------------------------------------------------
step "Install"

mkdir -p "$BACKUP_DIR"
for bin in "syscoin-${VER}/bin/"*; do
    old="$BIN_DIR/$(basename "$bin")"
    if [ -e "$old" ]; then
        cp -p "$old" "$BACKUP_DIR/"
    fi
done
ok "Backup of current binaries ${DIM}${BACKUP_SHOW}${NC}"

if ! install -m 0755 -o root -g root -t "$BIN_DIR" "syscoin-${VER}/bin/"*; then
    fail "Install failed."
    rollback || true
    start_node || fail "Failed to restart syscoind."
    exit 1
fi
ok "Installed Syscoin ${VER} ${DIM}${BIN_DIR}${NC}"

# Sentinel cleanup (Sentinel is no longer used since Syscoin 4)
rm -rf /root/sentinel
if current_crontab=$(crontab -l 2> /dev/null) && grep -q sentinel <<< "$current_crontab"; then
    sed '/sentinel/s/^\([^#]\)/#\1/' <<< "$current_crontab" | crontab -
    ok "Disabled old Sentinel cron job"
fi

# ---------------------------------------------------------------------------
step "Start SyscoinCore"

# Ask the user what to do next, unless --action was given
if [ -z "$ACTION" ]; then
    if [ "$ASSUME_YES" -eq 1 ]; then
        ACTION="start"
    else
        echo -e "   How should SyscoinCore be started?"
        echo
        echo -e "     ${BLUE}1${NC}  Start normally           ${DIM}default, recommended${NC}"
        echo -e "     ${BLUE}2${NC}  Start with reindex       ${DIM}for data integrity issues${NC}"
        echo -e "     ${BLUE}3${NC}  Clean data and reboot    ${DIM}keeps syscoin.conf and wallets${NC}"
        echo -e "     ${BLUE}4${NC}  Cancel                   ${DIM}SyscoinCore stays STOPPED${NC}"
        echo
        user_choice=""
        printf '   %b%s%b Choice %b[1-4, Enter = 1]%b ' "$CYAN" "$I_ASK" "$NC" "$DIM" "$NC"
        read -r user_choice || true
        [ -t 0 ] || echo
        case "${user_choice:-1}" in
            1) ACTION="start" ;;
            2) ACTION="reindex" ;;
            3) ACTION="clean" ;;
            4) ACTION="cancel" ;;
            *)
                fail "Invalid choice. SyscoinCore is NOT running, start it with: syscoind -daemon"
                exit 1
                ;;
        esac
    fi
fi

case "$ACTION" in
    start) ;;
    reindex)
        info "Starting with -reindex, this can take a long time"
        START_ARGS=(-reindex)
        ;;
    clean)
        if [ ! -d "$DATA_DIR" ]; then
            fail "${DATA_DIR} not found."
            exit 1
        fi
        warn "This deletes all blockchain data in ${DATA_DIR} (syscoin.conf, wallet.dat and wallets/ are kept)."
        really=""
        if [ "$ASSUME_YES" -eq 1 ]; then
            really="YES"
        else
            printf '   %b%s%b Type %bYES%b to continue: ' "$CYAN" "$I_ASK" "$NC" "$BOLD" "$NC"
            read -r really || true
            [ -t 0 ] || echo
        fi
        if [ "$really" != "YES" ]; then
            info "Cleanup cancelled, starting SyscoinCore normally."
        else
            find "$DATA_DIR" -mindepth 1 -maxdepth 1 \
                ! -name 'syscoin.conf' ! -name 'wallet.dat' ! -name 'wallets' \
                -exec rm -rf {} +
            ok "Cleaned ${DATA_DIR}"
            info "Previous binaries are backed up in ${BACKUP_SHOW}"
            warn "Rebooting system in 3 seconds..."
            sleep 3
            reboot
            exit 0
        fi
        ;;
    cancel)
        warn "Cancelled. SyscoinCore is NOT running, start it with: syscoind -daemon"
        exit 0
        ;;
esac

if ! start_node "${START_ARGS[@]}"; then
    fail "syscoind failed to start with version ${VER}."
    if confirm "Roll back to the previous version (${INSTALLED_VER:-unknown})?"; then
        if rollback && start_node "${START_ARGS[@]}"; then
            ok "Rolled back, syscoind is running again with ${INSTALLED_VER:-the previous version}."
        else
            fail "Rollback failed, please check manually."
        fi
    fi
    exit 1
fi
ok "syscoind is running"

# ---------------------------------------------------------------------------
step "Health check"

BLOCKS="" MN_STATE=""
if BLOCKS=$(spin_run "Waiting for RPC to become available" timeout 300 syscoin-cli -rpcwait getblockcount); then
    ok "RPC is available, block height ${BOLD}${BLOCKS}${NC}"
    MN_STATUS=$(syscoin-cli masternode status 2> /dev/null || true)
    MN_STATE=$(grep -oE '"(state|status)": *"[^"]*"' <<< "$MN_STATUS" | head -n1 | sed 's/.*: *"//; s/"$//' || true)
    if [ "$MN_STATE" = "READY" ] || [ "$MN_STATE" = "Ready" ]; then
        ok "Masternode status ${GREEN}${MN_STATE}${NC}"
    else
        warn "Masternode status: ${MN_STATE:-unknown}"
        if [ -n "$MN_STATUS" ]; then
            sed "s/^/     /" <<< "$MN_STATUS"
        fi
    fi
else
    fail "RPC did not become available within 5 minutes, check debug.log."
fi

if [ "$MN_STATE" = "READY" ] || [ "$MN_STATE" = "Ready" ]; then
    MN_SUMMARY="${GREEN}${MN_STATE}${NC}"
else
    MN_SUMMARY="${ORANGE}${MN_STATE:-unknown}${NC}"
fi
summary_box "Summary" \
    "Version=${BOLD}${VER}${NC}${INSTALLED_VER:+ ${DIM}(was ${INSTALLED_VER})${NC}}" \
    "Block height=${BLOCKS:-unknown}" \
    "Masternode=${MN_SUMMARY}" \
    "Backup=${BACKUP_SHOW}" \
    "Duration=$((SECONDS / 60))m $((SECONDS % 60))s"

echo
show_coin 2 "${GREEN}${BOLD}Done!${NC} Syscoin ${VER} is running." "${PURPLE}Thanks for running a Syscoin masternode!${NC}"
echo -e "${DIM}Liked it? Syscoin tip jar:${NC} ${ORANGE}sys1qpqnzpdg4thlktvzgkpazzh3yduh8ctum2eguxe${NC}"
