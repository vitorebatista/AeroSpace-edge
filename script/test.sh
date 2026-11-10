#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

./script/build-debug.sh -Xswiftc -warnings-as-errors
./script/swift-test.sh

./.debug/aerospace-edge -h > /dev/null
./.debug/aerospace-edge --help > /dev/null
./.debug/aerospace-edge -v | grep -q "0.0.0-SNAPSHOT SNAPSHOT"
./.debug/aerospace-edge --version | grep -q "0.0.0-SNAPSHOT SNAPSHOT"

./script/lint.sh
./script/generate.sh
./script/check-uncommitted-files.sh

echo
echo "✅ All tests have passed successfully"
