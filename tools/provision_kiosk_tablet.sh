#!/usr/bin/env bash

set -uo pipefail

APP_PACKAGE="uz.neovex.iccu.kiosk"
MAIN_ACTIVITY="uz.neovex.iccu.kiosk/.MainActivity"
ADMIN_RECEIVER="uz.neovex.iccu.kiosk/.KioskDeviceAdminReceiver"
APK_RELATIVE_PATH="app/build/outputs/apk/debug/app-debug.apk"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADB_BIN="${ADB:-}"
SERIAL=""
SKIP_BUILD=0
RUN_TESTS=1

if [[ -t 1 ]]; then
  GREEN="$(printf '\033[32m')"
  YELLOW="$(printf '\033[33m')"
  RED="$(printf '\033[31m')"
  BOLD="$(printf '\033[1m')"
  RESET="$(printf '\033[0m')"
else
  GREEN=""
  YELLOW=""
  RED=""
  BOLD=""
  RESET=""
fi

print_usage() {
  cat <<USAGE
ICCU Forum Kiosk tablet provisioning

Usage:
  ./tools/provision_kiosk_tablet.sh
  ./tools/provision_kiosk_tablet.sh --serial KZ5CAEJ85LX5DSZFRYW
  ./tools/provision_kiosk_tablet.sh --skip-build
  ./tools/provision_kiosk_tablet.sh --no-tests

What it does:
  1. Finds the connected ADB tablet
  2. Builds the APK unless --skip-build is used
  3. Installs the APK
  4. Sets Device Owner
  5. Sets the kiosk app as Home
  6. Enables immersive fullscreen
  7. Launches the app
  8. Verifies mLockTaskModeState=LOCKED

Before running:
  - Tablet must have Developer options enabled
  - USB debugging must be enabled and authorized
  - For first Device Owner setup, tablet must not have Google/accounts
USAGE
}

log() {
  printf '%s\n' "${BOLD}==>${RESET} $*"
}

ok() {
  printf '%s\n' "${GREEN}OK:${RESET} $*"
}

warn() {
  printf '%s\n' "${YELLOW}WARN:${RESET} $*"
}

fail() {
  printf '%s\n' "${RED}ERROR:${RESET} $*" >&2
  exit 1
}

run() {
  log "$*"
  "$@" || fail "Command failed: $*"
}

adb_device() {
  "$ADB_BIN" -s "$SERIAL" "$@"
}

refresh_adb_connection() {
  warn "Refreshing ADB connection"
  "$ADB_BIN" kill-server >/dev/null 2>&1 || true
  "$ADB_BIN" start-server >/dev/null 2>&1 || true

  if [[ "$SERIAL" == *:* ]]; then
    "$ADB_BIN" disconnect "$SERIAL" >/dev/null 2>&1 || true
    "$ADB_BIN" connect "$SERIAL" >/dev/null 2>&1 || true
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --serial|-s)
        [[ $# -ge 2 ]] || fail "--serial requires a value"
        SERIAL="$2"
        shift 2
        ;;
      --skip-build)
        SKIP_BUILD=1
        shift
        ;;
      --no-tests)
        RUN_TESTS=0
        shift
        ;;
      --help|-h)
        print_usage
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done
}

require_tools() {
  if [[ -n "$ADB_BIN" ]]; then
    [[ -x "$ADB_BIN" ]] || command -v "$ADB_BIN" >/dev/null 2>&1 || fail "ADB=$ADB_BIN is not executable"
  elif command -v adb >/dev/null 2>&1; then
    ADB_BIN="adb"
  elif [[ -x "$HOME/Library/Android/sdk/platform-tools/adb" ]]; then
    ADB_BIN="$HOME/Library/Android/sdk/platform-tools/adb"
  elif [[ -n "${ANDROID_HOME:-}" && -x "$ANDROID_HOME/platform-tools/adb" ]]; then
    ADB_BIN="$ANDROID_HOME/platform-tools/adb"
  elif [[ -n "${ANDROID_SDK_ROOT:-}" && -x "$ANDROID_SDK_ROOT/platform-tools/adb" ]]; then
    ADB_BIN="$ANDROID_SDK_ROOT/platform-tools/adb"
  else
    fail "adb not found. Install Android Platform Tools, install Android Studio, or set ADB=/path/to/adb."
  fi

  [[ -x "$PROJECT_ROOT/gradlew" ]] || fail "gradlew not found or not executable in $PROJECT_ROOT"
}

device_state_for_serial() {
  local wanted="$1"
  "$ADB_BIN" devices | awk -v serial="$wanted" '$1 == serial { print $2 }'
}

select_device() {
  run "$ADB_BIN" start-server

  if [[ -n "$SERIAL" ]]; then
    local state
    state="$(device_state_for_serial "$SERIAL")"
    [[ "$state" == "device" ]] || fail "Device $SERIAL is not ready. Current state: ${state:-not found}. Run: adb devices"
    ok "Using tablet $SERIAL"
    return
  fi

  mapfile -t ready_devices < <("$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" { print $1 }')
  mapfile -t unauthorized_devices < <("$ADB_BIN" devices | awk 'NR > 1 && $2 == "unauthorized" { print $1 }')
  mapfile -t offline_devices < <("$ADB_BIN" devices | awk 'NR > 1 && $2 == "offline" { print $1 }')

  if [[ ${#ready_devices[@]} -eq 1 ]]; then
    SERIAL="${ready_devices[0]}"
    ok "Using tablet $SERIAL"
    return
  fi

  if [[ ${#ready_devices[@]} -gt 1 ]]; then
    printf '%s\n' "More than one tablet is connected:"
    printf '  %s\n' "${ready_devices[@]}"
    fail "Run again with --serial DEVICE_SERIAL"
  fi

  if [[ ${#unauthorized_devices[@]} -gt 0 ]]; then
    printf '%s\n' "Unauthorized device(s):"
    printf '  %s\n' "${unauthorized_devices[@]}"
    fail "Approve the USB debugging prompt on the tablet, then run this script again."
  fi

  if [[ ${#offline_devices[@]} -gt 0 ]]; then
    printf '%s\n' "Offline device(s):"
    printf '  %s\n' "${offline_devices[@]}"
    fail "Reconnect the tablet or run: adb kill-server && adb start-server"
  fi

  fail "No ready tablet found. Connect one tablet and run: adb devices"
}

build_apk() {
  if [[ "$SKIP_BUILD" -eq 1 ]]; then
    warn "Skipping build because --skip-build was used"
    [[ -f "$PROJECT_ROOT/$APK_RELATIVE_PATH" ]] || fail "APK does not exist: $PROJECT_ROOT/$APK_RELATIVE_PATH"
    return
  fi

  cd "$PROJECT_ROOT" || fail "Cannot cd to project root: $PROJECT_ROOT"
  if [[ "$RUN_TESTS" -eq 1 ]]; then
    run ./gradlew testDebugUnitTest assembleDebug
  else
    run ./gradlew assembleDebug
  fi

  [[ -f "$PROJECT_ROOT/$APK_RELATIVE_PATH" ]] || fail "Build finished but APK was not found: $PROJECT_ROOT/$APK_RELATIVE_PATH"
  ok "APK ready: $APK_RELATIVE_PATH"
}

install_apk() {
  log "Installing APK"
  local output
  if output="$(adb_device install -r "$PROJECT_ROOT/$APK_RELATIVE_PATH" 2>&1)"; then
    printf '%s\n' "$output"
    ok "APK installed"
    return
  fi

  printf '%s\n' "$output" >&2
  if printf '%s' "$output" | grep -qi "closed"; then
    refresh_adb_connection
    log "Retrying APK install"
    if output="$(adb_device install -r "$PROJECT_ROOT/$APK_RELATIVE_PATH" 2>&1)"; then
      printf '%s\n' "$output"
      ok "APK installed"
      return
    fi
    printf '%s\n' "$output" >&2

    log "Retrying APK install with --no-streaming"
    if output="$(adb_device install --no-streaming -r "$PROJECT_ROOT/$APK_RELATIVE_PATH" 2>&1)"; then
      printf '%s\n' "$output"
      ok "APK installed"
      return
    fi
    printf '%s\n' "$output" >&2
  fi

  fail "APK install failed"
}

ensure_device_owner() {
  local current_owner
  current_owner="$(adb_device shell dpm get-device-owner 2>/dev/null || true)"

  if printf '%s' "$current_owner" | grep -q "$APP_PACKAGE"; then
    ok "Device Owner already set to $APP_PACKAGE"
    return
  fi

  log "Setting Device Owner"
  local output
  if output="$(adb_device shell dpm set-device-owner "$ADMIN_RECEIVER" 2>&1)"; then
    printf '%s\n' "$output"
    ok "Device Owner enabled"
    return
  fi

  printf '%s\n' "$output" >&2
  printf '\n%s\n' "Device Owner setup failed. Most common fixes:"
  printf '%s\n' "- Remove Google/account(s) from the tablet"
  printf '%s\n' "- Factory reset the tablet, do not add an account, enable USB debugging, then run this script"
  printf '%s\n' "- Make sure the APK was installed before Device Owner setup"
  fail "Cannot continue without Device Owner"
}

configure_kiosk() {
  run adb_device shell cmd package set-home-activity "$MAIN_ACTIVITY"
  run adb_device shell settings put global policy_control 'immersive.full=*'
  ok "Home activity and immersive fullscreen configured"
}

launch_app() {
  run adb_device shell am force-stop "$APP_PACKAGE"
  run adb_device shell monkey -p "$APP_PACKAGE" 1
  sleep 8
  ok "Kiosk app launched"
}

verify_kiosk() {
  log "Verifying kiosk lock"
  local activity_dump
  activity_dump="$(adb_device shell dumpsys activity activities 2>/dev/null || true)"

  if ! printf '%s' "$activity_dump" | grep -q "$APP_PACKAGE"; then
    fail "Kiosk app is not visible in running activities"
  fi

  if ! printf '%s' "$activity_dump" | grep -q "mLockTaskModeState=LOCKED"; then
    printf '%s\n' "$activity_dump" | grep -E "mLockTaskModeState|$APP_PACKAGE" -C 2 || true
    fail "Kiosk is not locked. Expected: mLockTaskModeState=LOCKED"
  fi

  ok "Kiosk verified: mLockTaskModeState=LOCKED"
}

main() {
  parse_args "$@"
  require_tools

  printf '%s\n' "${BOLD}ICCU Forum Kiosk provisioning${RESET}"
  printf '%s\n' "Project: $PROJECT_ROOT"
  printf '%s\n' "Package: $APP_PACKAGE"
  printf '\n'

  select_device
  build_apk
  install_apk
  ensure_device_owner
  configure_kiosk
  launch_app
  verify_kiosk

  printf '\n%s\n' "${GREEN}DONE:${RESET} tablet $SERIAL is ready for kiosk use."
}

main "$@"
