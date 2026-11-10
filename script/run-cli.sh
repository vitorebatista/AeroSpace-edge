#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

./script/build-debug.sh > /dev/null || ./script/build-debug.sh
./.debug/aerospace-edge "$@"
