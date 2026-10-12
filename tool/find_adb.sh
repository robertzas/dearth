# Sourced by tool/deploy_frame.sh and tool/perf_gate.sh: sets ADB to the adb
# on PATH, else the Android SDK's platform-tools (empty when there is none).
ADB="$(command -v adb || true)"
if [ -z "$ADB" ]; then
  for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" /opt/android-sdk "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    if [ -n "$sdk" ] && [ -x "$sdk/platform-tools/adb" ]; then ADB="$sdk/platform-tools/adb"; break; fi
  done
fi
