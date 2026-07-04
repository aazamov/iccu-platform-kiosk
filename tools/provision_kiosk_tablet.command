#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/provision_kiosk_tablet.sh" "$@"
EXIT_CODE=$?

if [[ "$EXIT_CODE" -ne 0 ]]; then
  printf '\nProvisioning failed with exit code %s.\n' "$EXIT_CODE"
fi

printf '\nPress Enter to close this window...'
read -r _
exit "$EXIT_CODE"
