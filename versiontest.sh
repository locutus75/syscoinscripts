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

tag_url="https://github.com/syscoin/syscoin/releases/latest/"
echo $tag_url
tag_get="tag_name=v"
echo $tag_get
tag_grep=$(curl -sL $tag_url | grep -o -m1 "$tag_get\?[0-9]*\.[0-9]*\.[0-9]*")
echo $tag_grep
((tag_pos=${#tag_get}+1))
tag_ver=$(echo "$tag_grep" | cut -c$tag_pos-)
echo $tag_ver

VER=$tag_ver

echo -e "${PURPLE}Updating Syscoin Masternode Versie ${VER}${NC}"
