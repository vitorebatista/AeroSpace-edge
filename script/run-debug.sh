#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

./script/build-debug.sh
./.debug/AeroSpaceApp "$@"
