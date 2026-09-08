#!/usr/bin/env bash
# `mobile:build-android`: real Gradle build of the
# Capacitor Android project, producing an installable unsigned debug APK.
#
# Kept in a script rather than inline moon.yml `args`: moon statically
# pre-substitutes `$IDENTIFIER` in `args` from its own environment, which
# blanks a variable this script exports and re-reads (BAALBEK_GRADLE_BUILD_DIR).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

bash scripts/setup-android-sdk.sh
pnpm install --frozen-lockfile
# `pnpm exec`, not `npx`: proto ships no npx shim, so npx is a system Node.
pnpm exec cap sync android

# 10.0.2.2 is the Android emulator's alias for the host machine, so the default
# reaches a `server` running on the developer's own port 4004.
bash scripts/stamp-api-config.sh \
  android/app/src/main/assets/public \
  "${MOBILE_API_BASE_URL:-http://10.0.2.2:4004/api/json/core}"

export ANDROID_SDK_ROOT="$HOME/.android-sdk"
export ANDROID_HOME="$HOME/.android-sdk"
export GRADLE_USER_HOME="$HOME/.cache/baalbek-gradle"
export BAALBEK_GRADLE_BUILD_DIR="$HOME/.cache/baalbek-gradle-build/mobile-android"

# gradlew prefers $JAVA_HOME/bin/java over PATH, so pin it to proto's JDK
# (.prototools `java`) or an inherited JAVA_HOME would override the pin.
PROTO_JAVA="${PROTO_HOME:-$HOME/.proto}/bin/java"
[ -e "$PROTO_JAVA" ] || { echo "error: no proto-managed java at $PROTO_JAVA. Run: proto install java" >&2; exit 1; }
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$PROTO_JAVA")")")"
export JAVA_HOME

cd android
./gradlew --init-script ../scripts/external-build-dir.init.gradle assembleDebug --no-daemon

mkdir -p app/build/outputs/apk/debug
cp "$BAALBEK_GRADLE_BUILD_DIR/app/outputs/apk/debug/app-debug.apk" app/build/outputs/apk/debug/app-debug.apk
