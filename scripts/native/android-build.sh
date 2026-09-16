#!/usr/bin/env bash
# Debug APK for the emulator. x86_64 only: the CI emulator is x86_64, and
# building the other three ABIs quadruples the NDK work for nothing. Override
# with WORKFLOWS_ANDROID_ABIS=arm64-v8a to run against an Apple-silicon emulator
# locally (an x86_64 APK fails there with INSTALL_FAILED_NO_MATCHING_ABIS).
# --no-daemon because the runner is thrown away after the job.
# Needs: prebuild.sh android.
# Output: android/app/build/outputs/apk/debug/app-debug.apk
# Usage: android-build.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/e2e-env.sh"

root="$(consumer_root)"
[ -x "$root/android/gradlew" ] || die "no android/gradlew in $root - run prebuild.sh android first"
cd "$root/android"

group "gradlew :app:assembleDebug"
./gradlew :app:assembleDebug \
  -PreactNativeArchitectures="${WORKFLOWS_ANDROID_ABIS:-x86_64}" --no-daemon --build-cache
endgroup

apk="$root/$WORKFLOWS_ANDROID_APK"
[ -f "$apk" ] || die "assembleDebug succeeded but $apk is missing"
log "built $apk"
gh_output apk "$apk"
