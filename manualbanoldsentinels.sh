#!/bin/bash
for mnbanlist in $(./syscoin-cli masternodelist json | grep 1.1.0 -B5 -F | grep address | cut -c 17-31 | awk -F: '{print $1}')
do
./syscoin-cli setban $mnbanlist add 2629800
done
