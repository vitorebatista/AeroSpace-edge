#!/usr/bin/env bash
cd "$(dirname "$0")/.."
source ./script/setup.sh

snapshot_version="0.0.0-SNAPSHOT"
build_version="$snapshot_version"
codesign_identity="aerospace-codesign-certificate"
allow_adhoc=0

# The certificate every published release is signed with. macOS stores the app's *designated
# requirement* when the user grants Accessibility or Screen Recording and re-checks it on every
# launch, so this leaf hash is effectively part of the app's identity to TCC: change it and every
# user silently loses both grants. See "Signing identity" in dev-docs/fork-maintenance.md.
release_cert_leaf="bb9c2ac177c6a90115bcf04c071e14cd1004c549"

while test $# -gt 0; do
    case $1 in
        --build-version) build_version="$2"; shift 2;;
        --codesign-identity) codesign_identity="$2"; shift 2;;
        --allow-adhoc) allow_adhoc=1; shift;;
        *) echo "Unknown option $1" > /dev/stderr; exit 1 ;;
    esac
done

# An ad-hoc signature has no certificate, so the designated requirement degrades to the literal
# binary hash (`cdhash H"..."`), which changes with every build. macOS then treats each update as a
# different app and drops the Accessibility and Screen Recording grants — and the dead TCC entry
# blocks re-granting until the user runs `tccutil reset`. Releases v1.12-v1.15 shipped that way.
# Fail fast rather than spend a full release build producing an artifact that must not be published.
if test "$codesign_identity" == "-" && test "$allow_adhoc" == 0; then
    echo "Refusing to build with an ad-hoc signature (--codesign-identity -)." > /dev/stderr
    echo "It breaks the user's Accessibility and Screen Recording grants on every update." > /dev/stderr
    echo "Sign with 'aerospace-codesign-certificate' (script/create-codesign-certificate.sh)," > /dev/stderr
    echo "or pass --allow-adhoc for a throwaway build that will never be published (CI does that)." > /dev/stderr
    exit 1
fi

#############
### BUILD ###
#############

./script/build-docs.sh
./script/build-shell-completion.sh

./script/generate.sh
./script/check-uncommitted-files.sh

# Version and git hash are embedded as a Mach-O section (read by Sources/Common/buildInfo.swift),
# so the build no longer rewrites tracked sources and leaves the git tree clean even on failure.
build_info_file="$PWD/.build-info.txt"
printf '%s\n%s\n%s\n' "$build_version" "$(git rev-parse HEAD)" "$(git rev-parse --short HEAD)" > "$build_info_file"

swift_build_cli=(build -c release --arch arm64 --arch x86_64 --product aerospace-edge)
swift "${swift_build_cli[@]}" -Xswiftc -warnings-as-errors \
    -Xlinker -sectcreate \
    -Xlinker __TEXT \
    -Xlinker __aero_build \
    -Xlinker "$build_info_file"
cli_bin_path="$(swift "${swift_build_cli[@]}" --show-bin-path)"

rm -rf .release && mkdir .release

cd ./xcode
    xcode_configuration="Release"
    xcodebuild -version
    xcodebuild-pretty ../.release/xcodebuild.log clean build \
        -scheme AeroSpace \
        -destination "generic/platform=macOS" \
        -configuration "$xcode_configuration" \
        -derivedDataPath .xcode-build \
        MARKETING_VERSION="$build_version" \
        AEROSPACE_CODE_SIGN_IDENTITY="$codesign_identity" \
        AEROSPACE_BUILD_INFO_LDFLAGS="-sectcreate __TEXT __aero_build $build_info_file"
cd -

cp -r "xcode/.xcode-build/Build/Products/$xcode_configuration/AeroSpace-edge.app" .release
cp -r "$cli_bin_path/aerospace-edge" .release

# Binary reproducibility: strip non-portable rpaths
# https://github.com/swiftlang/swift-package-manager/issues/10760
xcrun objdump --macho --rpaths --no-leading-headers --arch all .release/aerospace-edge | grep -vE '^(@|/usr/lib/swift$)' | sort -u |
    while IFS= read -r rpath; do
        install_name_tool -delete_rpath "$rpath" .release/aerospace-edge
    done

################
### SIGN CLI ###
################

codesign -s "$codesign_identity" .release/aerospace-edge

################
### VALIDATE ###
################

./script/validate-release-binaries.sh || exit 1

# `codesign -v` (in validate-release-binaries.sh) passes happily on an ad-hoc signature, so it cannot catch the case above on its own
# (this script has no `set -e` either: a failed `codesign -s` would otherwise sail through). Check
# what actually matters to TCC instead — the designated requirement of the shipped artifacts.
check-designated-requirement() {
    local file="$1"
    local dr
    test "$allow_adhoc" == 1 && return 0 # throwaway build, opted in above
    # codesign prints the ad-hoc case commented out ('# designated => cdhash H"..."'), because a
    # hash pin is not a real requirement expression. Strip the marker so both forms are comparable.
    dr="$(codesign -d -r- "$file" 2>/dev/null | sed -n 's/^#* *designated => //p')"

    if [[ "$dr" == *'cdhash H"'* ]]; then
        echo "!!! $file is ad-hoc signed !!!" > /dev/stderr
        echo "    designated => $dr" > /dev/stderr
        echo "Its designated requirement is the binary hash, so it changes with every build." > /dev/stderr
        exit 1
    fi

    if test "$build_version" != "$snapshot_version" &&
        [[ "$dr" != *"certificate leaf = H\"$release_cert_leaf\""* ]]; then
        echo "!!! $file is signed by an unexpected certificate !!!" > /dev/stderr
        echo "    designated => $dr" > /dev/stderr
        echo "    expected    => certificate leaf = H\"$release_cert_leaf\"" > /dev/stderr
        echo "Users' grants are pinned to the requirement previous releases shipped; publishing a" > /dev/stderr
        echo "different one silently revokes them. Restore the backed-up .p12, or update" > /dev/stderr
        echo "release_cert_leaf at the top of this script if the change is deliberate." > /dev/stderr
        exit 1
    fi
}

check-designated-requirement .release/AeroSpace-edge.app
check-designated-requirement .release/aerospace-edge

############
### PACK ###
############

mkdir -p ".release/AeroSpace-edge-v$build_version/manpage" && cp .man/*.1 ".release/AeroSpace-edge-v$build_version/manpage"
cp -r ./legal ".release/AeroSpace-edge-v$build_version/legal"
cp -r .shell-completion ".release/AeroSpace-edge-v$build_version/shell-completion"
cd .release
    mkdir -p "AeroSpace-edge-v$build_version/bin" && cp -r aerospace-edge "AeroSpace-edge-v$build_version/bin"
    cp -r AeroSpace-edge.app "AeroSpace-edge-v$build_version"
    zip -r "AeroSpace-edge-v$build_version.zip" "AeroSpace-edge-v$build_version"
cd -

#################
### Brew Cask ###
#################
for cask_name in aerospace-edge aerospace-edge-dev; do
    ./script/build-brew-cask.sh \
        --cask-name "$cask_name" \
        --zip-uri ".release/AeroSpace-edge-v$build_version.zip" \
        --build-version "$build_version"
done
