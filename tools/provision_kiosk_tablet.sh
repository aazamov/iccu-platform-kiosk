#!/usr/bin/env bash

set -uo pipefail

SCRIPT_VERSION="2026-07-03.10-mac"
APP_PACKAGE="uz.neovex.iccu.kiosk"
MAIN_ACTIVITY="uz.neovex.iccu.kiosk/.MainActivity"
ADMIN_RECEIVER="uz.neovex.iccu.kiosk/.KioskDeviceAdminReceiver"
WIFI_PROVISION_RECEIVER="uz.neovex.iccu.kiosk/.WifiProvisionReceiver"
WIFI_PROVISION_ACTION="uz.neovex.iccu.kiosk.PROVISION_WIFI"
WEBVIEW_PACKAGE="com.google.android.webview"
APK_RELATIVE_PATH="app/build/outputs/apk/debug/app-debug.apk"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOADS_ROOT="$PROJECT_ROOT/tools/.downloads"
ADB_BIN="${ADB:-}"
SERIAL=""
SKIP_BUILD=0
RUN_TESTS=1
SINGLE_DEVICE=0
SKIP_WEBVIEW_UPDATE=0
WEBVIEW_APK=""
MINIMUM_WEBVIEW_MAJOR=100
WIFI_SSID="Neo_wifi"
WIFI_PASSWORD="12345678!!"
SKIP_WIFI_SETUP=0
WIFI_CONNECT_TIMEOUT_SECONDS=35

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
ICCU Forum Kiosk macOS/Linux provisioning

Usage:
  ./tools/provision_kiosk_tablet.sh
  ./tools/provision_kiosk_tablet.sh --serial DEVICE_SERIAL
  ./tools/provision_kiosk_tablet.sh --skip-build
  ./tools/provision_kiosk_tablet.sh --no-tests
  ./tools/provision_kiosk_tablet.sh --single-device

What it does:
  1. Finds all connected authorized ADB tablets unless --serial is used
  2. Tries Wi-Fi connection to $WIFI_SSID
  3. Updates Android System WebView when it is older than major $MINIMUM_WEBVIEW_MAJOR
  4. Builds the APK once unless --skip-build is used
  5. Installs the APK
  6. Sets Device Owner
  7. Retries Wi-Fi through the Device Owner kiosk app if ADB Wi-Fi is blocked
  8. Sets kiosk app as Home, launches it, and verifies lock-task mode

Options:
  --webview-apk PATH              Use a specific Android System WebView APK
  --skip-webview-update           Do not update Android System WebView
  --minimum-webview-major NUMBER  Default: $MINIMUM_WEBVIEW_MAJOR
  --wifi-ssid SSID                Default: $WIFI_SSID
  --wifi-password PASSWORD        Default is stored in the script
  --skip-wifi-setup               Do not configure Wi-Fi
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

capture_adb_device() {
  adb_device "$@" 2>&1
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
      --single-device)
        SINGLE_DEVICE=1
        shift
        ;;
      --webview-apk)
        [[ $# -ge 2 ]] || fail "--webview-apk requires a value"
        WEBVIEW_APK="$2"
        shift 2
        ;;
      --skip-webview-update)
        SKIP_WEBVIEW_UPDATE=1
        shift
        ;;
      --minimum-webview-major)
        [[ $# -ge 2 ]] || fail "--minimum-webview-major requires a value"
        MINIMUM_WEBVIEW_MAJOR="$2"
        shift 2
        ;;
      --wifi-ssid)
        [[ $# -ge 2 ]] || fail "--wifi-ssid requires a value"
        WIFI_SSID="$2"
        shift 2
        ;;
      --wifi-password)
        [[ $# -ge 2 ]] || fail "--wifi-password requires a value"
        WIFI_PASSWORD="$2"
        shift 2
        ;;
      --skip-wifi-setup)
        SKIP_WIFI_SETUP=1
        shift
        ;;
      --wifi-timeout)
        [[ $# -ge 2 ]] || fail "--wifi-timeout requires a value"
        WIFI_CONNECT_TIMEOUT_SECONDS="$2"
        shift 2
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
    if [[ -x "$ADB_BIN" ]]; then
      :
    elif command -v "$ADB_BIN" >/dev/null 2>&1; then
      ADB_BIN="$(command -v "$ADB_BIN")"
    else
      fail "ADB=$ADB_BIN is not executable"
    fi
  elif command -v adb >/dev/null 2>&1; then
    ADB_BIN="$(command -v adb)"
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

refresh_adb_connection() {
  warn "Refreshing ADB connection"
  "$ADB_BIN" kill-server >/dev/null 2>&1 || true
  "$ADB_BIN" start-server >/dev/null 2>&1 || true

  if [[ "$SERIAL" == *:* ]]; then
    "$ADB_BIN" disconnect "$SERIAL" >/dev/null 2>&1 || true
    "$ADB_BIN" connect "$SERIAL" >/dev/null 2>&1 || true
  fi
}

device_state_for_serial() {
  local wanted="$1"
  "$ADB_BIN" devices | awk -v serial="$wanted" '$1 == serial { print $2 }'
}

select_target_devices() {
  run "$ADB_BIN" start-server

  TARGETS=()
  if [[ -n "$SERIAL" ]]; then
    local state
    state="$(device_state_for_serial "$SERIAL")"
    [[ "$state" == "device" ]] || fail "Device $SERIAL is not ready. Current state: ${state:-not found}. Run: adb devices"
    TARGETS=("$SERIAL")
    ok "Using tablet $SERIAL"
    return
  fi

  local ready_devices=()
  local unauthorized_devices=()
  local offline_devices=()
  local line serial state
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    serial="$(printf '%s\n' "$line" | awk '{ print $1 }')"
    state="$(printf '%s\n' "$line" | awk '{ print $2 }')"
    case "$state" in
      device) ready_devices+=("$serial") ;;
      unauthorized) unauthorized_devices+=("$serial") ;;
      offline) offline_devices+=("$serial") ;;
    esac
  done < <("$ADB_BIN" devices | awk 'NR > 1 { print }')

  if [[ ${#ready_devices[@]} -eq 1 ]]; then
    TARGETS=("${ready_devices[0]}")
    SERIAL="${ready_devices[0]}"
    ok "Using tablet $SERIAL"
    return
  fi

  if [[ ${#ready_devices[@]} -gt 1 && "$SINGLE_DEVICE" -eq 0 ]]; then
    TARGETS=("${ready_devices[@]}")
    ok "Using all ready tablets: ${#TARGETS[@]}"
    printf '  %s\n' "${TARGETS[@]}"
    if [[ ${#unauthorized_devices[@]} -gt 0 ]]; then
      warn "Skipping unauthorized tablet(s). Approve USB debugging and run again for them:"
      printf '  %s\n' "${unauthorized_devices[@]}"
    fi
    if [[ ${#offline_devices[@]} -gt 0 ]]; then
      warn "Skipping offline tablet(s):"
      printf '  %s\n' "${offline_devices[@]}"
    fi
    return
  fi

  if [[ ${#ready_devices[@]} -gt 1 ]]; then
    printf '%s\n' "More than one tablet is connected:"
    printf '  %s\n' "${ready_devices[@]}"
    fail "Run again with --serial DEVICE_SERIAL, or omit --single-device to install all ready tablets"
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

normalize_wifi_ssid() {
  sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/^"//; s/"$//; s/^<unknown ssid>$//'
}

current_wifi_ssid() {
  local output ssid
  output="$(capture_adb_device shell dumpsys connectivity || true)"
  ssid="$(printf '%s\n' "$output" | grep -E "NetworkAgentInfo\\{ ni\\{\\[type: WIFI|SSID=" | sed -nE 's/.*SSID="([^"]+)".*/\1/p; s/.*SSID: "([^"]+)".*/\1/p' | head -1 | normalize_wifi_ssid)"
  if [[ -n "$ssid" ]]; then
    printf '%s\n' "$ssid"
    return
  fi

  output="$(capture_adb_device shell cmd wifi status || true)"
  ssid="$(printf '%s\n' "$output" | grep -v "BSSID" | sed -nE 's/.*SSID:[[:space:]]*"([^"]+)".*/\1/p; s/.*SSID:[[:space:]]*([^,]+).*/\1/p' | head -1 | normalize_wifi_ssid)"
  if [[ -n "$ssid" ]]; then
    printf '%s\n' "$ssid"
    return
  fi

  output="$(capture_adb_device shell dumpsys wifi || true)"
  printf '%s\n' "$output" |
    grep -E "mWifiInfo|WifiInfo" |
    sed -nE 's/.*SSID:[[:space:]]*"([^"]+)".*/\1/p' |
    head -1 |
    normalize_wifi_ssid
}

wait_for_wifi_connected() {
  local timeout="$1"
  local deadline=$((SECONDS + timeout))
  local ssid=""

  while [[ $SECONDS -lt $deadline ]]; do
    sleep 3
    ssid="$(current_wifi_ssid)"
    if [[ "$ssid" == "$WIFI_SSID" ]]; then
      ok "Wi-Fi connected: $WIFI_SSID"
      return 0
    fi
  done

  if [[ -n "$ssid" ]]; then
    warn "Tablet is connected to Wi-Fi '$ssid', expected '$WIFI_SSID'"
  fi
  return 1
}

wifi_setup_skipped() {
  if [[ "$SKIP_WIFI_SETUP" -eq 1 ]]; then
    warn "Skipping Wi-Fi setup because --skip-wifi-setup was used"
    return 0
  fi
  if [[ -z "$WIFI_SSID" ]]; then
    warn "Skipping Wi-Fi setup because --wifi-ssid is empty"
    return 0
  fi
  return 1
}

ensure_wifi_connected() {
  if wifi_setup_skipped; then
    return
  fi

  local ssid
  ssid="$(current_wifi_ssid)"
  if [[ "$ssid" == "$WIFI_SSID" ]]; then
    ok "Wi-Fi already connected: $WIFI_SSID"
    return
  fi

  log "Connecting Wi-Fi to $WIFI_SSID"
  capture_adb_device shell svc wifi enable >/dev/null || true
  sleep 2

  local output
  if output="$(capture_adb_device shell cmd wifi connect-network "$WIFI_SSID" wpa2 "$WIFI_PASSWORD")"; then
    [[ -z "$output" ]] || printf '%s\n' "$output"
    if wait_for_wifi_connected "$WIFI_CONNECT_TIMEOUT_SECONDS"; then
      return
    fi
    warn "ADB Wi-Fi command completed, but the tablet did not connect yet. Will retry through the kiosk app after Device Owner is enabled."
    return
  fi

  printf '%s\n' "$output"
  if printf '%s' "$output" | grep -Eq "SecurityException|does not have access to wifi commands"; then
    warn "ADB shell cannot control Wi-Fi on this firmware. Will retry through the kiosk app after Device Owner is enabled."
  else
    warn "ADB Wi-Fi connect command failed. Will retry through the kiosk app after Device Owner is enabled."
  fi
}

ensure_wifi_connected_with_device_owner_app() {
  if wifi_setup_skipped; then
    return
  fi

  local ssid
  ssid="$(current_wifi_ssid)"
  if [[ "$ssid" == "$WIFI_SSID" ]]; then
    ok "Wi-Fi already connected: $WIFI_SSID"
    return
  fi

  log "Connecting Wi-Fi through kiosk Device Owner app"
  local output
  if output="$(capture_adb_device shell am broadcast -a "$WIFI_PROVISION_ACTION" -n "$WIFI_PROVISION_RECEIVER" --es ssid "$WIFI_SSID" --es password "$WIFI_PASSWORD")"; then
    printf '%s\n' "$output"
  else
    printf '%s\n' "$output" >&2
    fail "Could not send Wi-Fi provisioning broadcast to kiosk app"
  fi

  wait_for_wifi_connected "$WIFI_CONNECT_TIMEOUT_SECONDS" ||
    fail "Wi-Fi did not connect to $WIFI_SSID within $WIFI_CONNECT_TIMEOUT_SECONDS seconds"
}

current_webview_version() {
  local output version
  output="$(capture_adb_device shell dumpsys webviewupdate || true)"
  version="$(printf '%s\n' "$output" | sed -nE "s/.*Current WebView package \\(name, version\\): \\(${WEBVIEW_PACKAGE},[[:space:]]*([0-9][^)]+)\\).*/\\1/p" | head -1)"
  if [[ -n "$version" ]]; then
    printf '%s\n' "$version"
    return
  fi

  output="$(capture_adb_device shell dumpsys package "$WEBVIEW_PACKAGE" || true)"
  printf '%s\n' "$output" | sed -nE 's/.*versionName=([0-9][^[:space:]]+).*/\1/p' | head -1
}

version_major() {
  local version="$1"
  printf '%s\n' "${version%%.*}" | sed -E 's/[^0-9].*//'
}

resolve_webview_apk() {
  if [[ -n "$WEBVIEW_APK" ]]; then
    [[ -f "$WEBVIEW_APK" ]] || fail "WebView APK path is not valid: $WEBVIEW_APK"
    printf '%s\n' "$WEBVIEW_APK"
    return
  fi

  local candidate
  for candidate in \
    "$DOWNLOADS_ROOT/android-system-webview.apk" \
    "$DOWNLOADS_ROOT/android-system-webview-150.apk" \
    "$DOWNLOADS_ROOT/android-system-webview-149.apk" \
    "$PROJECT_ROOT/tools/android-system-webview.apk"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

install_webview_apk() {
  local apk_path="$1"
  log "Installing Android System WebView: $apk_path"

  local output
  if output="$(capture_adb_device install -r "$apk_path")"; then
    printf '%s\n' "$output"
    return
  fi

  printf '%s\n' "$output" >&2
  if printf '%s' "$output" | grep -qi "closed"; then
    refresh_adb_connection
    log "Retrying WebView install"
    if output="$(capture_adb_device install -r "$apk_path")"; then
      printf '%s\n' "$output"
      return
    fi
    printf '%s\n' "$output" >&2

    log "Retrying WebView install with --no-streaming"
    if output="$(capture_adb_device install --no-streaming -r "$apk_path")"; then
      printf '%s\n' "$output"
      return
    fi
    printf '%s\n' "$output" >&2
  fi

  fail "Android System WebView install failed"
}

ensure_webview_updated() {
  if [[ "$SKIP_WEBVIEW_UPDATE" -eq 1 ]]; then
    warn "Skipping WebView update because --skip-webview-update was used"
    return
  fi

  local current_version current_major
  current_version="$(current_webview_version)"
  current_major="$(version_major "$current_version")"
  current_major="${current_major:-0}"

  if [[ -n "$current_version" && "$current_major" -ge "$MINIMUM_WEBVIEW_MAJOR" ]]; then
    ok "Android System WebView is already new enough: $current_version"
    return
  fi

  if [[ -z "$current_version" ]]; then
    warn "Could not read current Android System WebView version"
  else
    warn "Android System WebView is old: $current_version. Minimum required major: $MINIMUM_WEBVIEW_MAJOR"
  fi

  local webview_apk_path
  webview_apk_path="$(resolve_webview_apk)"
  if [[ -z "$webview_apk_path" ]]; then
    printf '\n%s\n' "Put Android System WebView APK here, then run again:"
    printf '%s\n' "  tools/.downloads/android-system-webview.apk"
    printf '%s\n' "  tools/.downloads/android-system-webview-150.apk"
    fail "WebView APK is required because tablet WebView is old"
  fi

  install_webview_apk "$webview_apk_path"
  sleep 2

  local updated_version updated_major
  updated_version="$(current_webview_version)"
  updated_major="$(version_major "$updated_version")"
  updated_major="${updated_major:-0}"
  [[ -n "$updated_version" && "$updated_major" -ge "$MINIMUM_WEBVIEW_MAJOR" ]] ||
    fail "WebView update did not become active"

  ok "Android System WebView updated: $updated_version"
}

install_apk() {
  log "Installing APK"
  local output
  if output="$(capture_adb_device install -r "$PROJECT_ROOT/$APK_RELATIVE_PATH")"; then
    printf '%s\n' "$output"
    ok "APK installed"
    return
  fi

  printf '%s\n' "$output" >&2
  if printf '%s' "$output" | grep -qi "closed"; then
    refresh_adb_connection
    log "Retrying APK install"
    if output="$(capture_adb_device install -r "$PROJECT_ROOT/$APK_RELATIVE_PATH")"; then
      printf '%s\n' "$output"
      ok "APK installed"
      return
    fi
    printf '%s\n' "$output" >&2

    log "Retrying APK install with --no-streaming"
    if output="$(capture_adb_device install --no-streaming -r "$PROJECT_ROOT/$APK_RELATIVE_PATH")"; then
      printf '%s\n' "$output"
      ok "APK installed"
      return
    fi
    printf '%s\n' "$output" >&2
  fi

  fail "APK install failed"
}

device_owner_details() {
  local dpm_owner policy_dump
  dpm_owner="$(capture_adb_device shell dpm get-device-owner || true)"
  policy_dump="$(capture_adb_device shell dumpsys device_policy || true)"
  printf '%s\n' "$dpm_owner"
  printf '%s\n' "$policy_dump" | grep -Ei "Device Owner|device owner|admin=|ComponentInfo|mDeviceOwner" | head -20 || true
}

our_app_is_device_owner() {
  device_owner_details | grep -q "$APP_PACKAGE"
}

ensure_device_owner() {
  if our_app_is_device_owner; then
    ok "Device Owner already set to $APP_PACKAGE"
    return
  fi

  log "Setting Device Owner"
  local output
  if output="$(capture_adb_device shell dpm set-device-owner "$ADMIN_RECEIVER")"; then
    printf '%s\n' "$output"
    ok "Device Owner enabled"
    return
  fi

  printf '%s\n' "$output" >&2
  if printf '%s' "$output" | grep -q "device owner is already set"; then
    printf '\n%s\n' "Another Device Owner is already set on this tablet:"
    device_owner_details
    fail "Cannot replace existing Device Owner"
  fi

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
  activity_dump="$(capture_adb_device shell dumpsys activity activities || true)"

  if ! printf '%s' "$activity_dump" | grep -q "$APP_PACKAGE"; then
    fail "Kiosk app is not visible in running activities"
  fi

  if ! printf '%s' "$activity_dump" | grep -q "mLockTaskModeState=LOCKED"; then
    printf '%s\n' "$activity_dump" | grep -E "mLockTaskModeState|$APP_PACKAGE" -C 2 || true
    fail "Kiosk is not locked. Expected: mLockTaskModeState=LOCKED"
  fi

  ok "Kiosk verified: mLockTaskModeState=LOCKED"
}

provision_current_device() {
  ensure_wifi_connected
  ensure_webview_updated
  install_apk
  ensure_device_owner
  ensure_wifi_connected_with_device_owner_app
  configure_kiosk
  launch_app
  verify_kiosk
}

main() {
  parse_args "$@"
  require_tools

  printf '%s\n' "${BOLD}ICCU provisioning script version: $SCRIPT_VERSION${RESET}"
  printf '%s\n' "${BOLD}ICCU Forum Kiosk macOS/Linux provisioning${RESET}"
  printf '%s\n' "Project: $PROJECT_ROOT"
  printf '%s\n' "Package: $APP_PACKAGE"
  printf '%s\n' "ADB: $ADB_BIN"
  if [[ "$SKIP_WEBVIEW_UPDATE" -eq 1 ]]; then
    printf '%s\n' "WebView update: skipped"
  else
    printf '%s\n' "WebView minimum major: $MINIMUM_WEBVIEW_MAJOR"
  fi
  if [[ "$SKIP_WIFI_SETUP" -eq 1 ]]; then
    printf '%s\n' "Wi-Fi setup: skipped"
  else
    printf '%s\n' "Wi-Fi SSID: $WIFI_SSID"
  fi
  printf '\n'

  select_target_devices
  build_apk

  local results=()
  local target code
  for target in "${TARGETS[@]}"; do
    printf '\n%s\n' "================ TABLET $target ================"
    (
      SERIAL="$target"
      printf '%s\n' "Serial: $SERIAL"
      provision_current_device
    )
    code=$?
    results+=("$target:$code")
  done

  printf '\n%s\n' "${BOLD}Provisioning summary:${RESET}"
  local failed_count=0
  for result in "${results[@]}"; do
    target="${result%%:*}"
    code="${result##*:}"
    if [[ "$code" -eq 0 ]]; then
      printf '%s\n' "${GREEN}OK:${RESET} $target"
    else
      printf '%s\n' "${RED}FAILED:${RESET} $target (exit $code)"
      failed_count=$((failed_count + 1))
    fi
  done

  if [[ "$failed_count" -gt 0 ]]; then
    fail "$failed_count tablet(s) failed provisioning"
  fi

  printf '\n%s\n' "${GREEN}DONE:${RESET} ${#results[@]} tablet(s) are ready for kiosk use."
}

main "$@"
