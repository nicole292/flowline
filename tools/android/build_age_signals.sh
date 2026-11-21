#!/usr/bin/env bash
# Builds the age-signals Godot Android plugin into
# addons/flowline_age_signals/bin/flowline-age-signals.aar (commit that file).
# Uses the game's Gradle wrapper (android/build) and Android Studio's Java.
set -e
cd "$(dirname "$0")/../.."
export JAVA_HOME="${JAVA_HOME:-/c/Program Files/Android/Android Studio/jbr}"
android/build/gradlew -p tools/android/age_signals_plugin --no-daemon -q assembleRelease
cp tools/android/age_signals_plugin/build/outputs/aar/flowline-age-signals-release.aar \
   addons/flowline_age_signals/bin/flowline-age-signals.aar
ls -la addons/flowline_age_signals/bin/flowline-age-signals.aar
