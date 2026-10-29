#!/usr/bin/env bash
# Builds the signed release APK (arm64 phones) into build/flowline.apk.
# The signing key lives OUTSIDE the repo in C:/dev/flowline_keys -- back it up.
set -e
cd "$(dirname "$0")/.."
PROPS=/c/dev/flowline_keys/flowline-release.properties
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$(grep '^keystore=' $PROPS | cut -d= -f2-)
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=$(grep '^alias=' $PROPS | cut -d= -f2-)
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$(grep '^password=' $PROPS | cut -d= -f2-)
G=/c/dev/godot/Godot_v4.7.2-stable_win64_console.exe
mkdir -p build
"$G" --headless --path . --import >/dev/null 2>&1 || true
"$G" --headless --path . --export-release "Android Release" build/flowline.apk 2>&1 | grep -E "ERROR|DONE|Signed" || true
ls -la build/flowline.apk
