#!/usr/bin/env bash
# Builds the signed Google Play bundle into build/flowline.aab (preset "Android Play").
# Uses the Gradle build in android/build. The wrapper there is Gradle 9.3.1 because
# Android Studio's bundled Java is 25 and older Gradle can't run on it. Godot's
# last Gradle step (copying the bundle out) fails on Windows paths with Gradle 9,
# so the bundle is copied from Gradle's output folder here instead.
# The signing key lives OUTSIDE the repo in C:/dev/flowline_keys -- back it up.
set -e
cd "$(dirname "$0")/.."
PROPS=/c/dev/flowline_keys/flowline-release.properties
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=$(grep '^keystore=' $PROPS | cut -d= -f2-)
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=$(grep '^alias=' $PROPS | cut -d= -f2-)
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=$(grep '^password=' $PROPS | cut -d= -f2-)
G=/c/dev/godot/Godot_v4.7.2-stable_win64_console.exe
OUT=android/build/build/outputs/bundle/standardRelease/build-standard-release.aab
mkdir -p build
rm -f "$OUT"
# The Godot engine libraries (200 MB) are not in git: take them from the export template.
if [ ! -d android/build/libs/release ]; then
  python -c "import zipfile,os; z=zipfile.ZipFile(os.path.expanduser('~/AppData/Roaming/Godot/export_templates/4.7.2.stable/android_source.zip')); [z.extract(n,'android/build') for n in z.namelist() if n.startswith('libs/')]"
fi
"$G" --headless --path . --import >/dev/null 2>&1 || true
"$G" --headless --path . --export-release "Android Play" build/flowline.aab > build/aab_log.txt 2>&1 || true
if [ ! -f "$OUT" ]; then
  grep -A3 "What went wrong" build/aab_log.txt || tail -20 build/aab_log.txt
  exit 1
fi
cp "$OUT" build/flowline.aab
ls -la build/flowline.aab
