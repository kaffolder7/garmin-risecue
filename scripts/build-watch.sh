#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FALLBACK_SDK_BIN="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin"
SDKS_DIR="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"

find_latest_sdk_bin() {
  if [[ ! -d "$SDKS_DIR" ]]; then
    return 0
  fi

  if sort -V </dev/null >/dev/null 2>&1; then
    find "$SDKS_DIR" -maxdepth 1 -type d -name 'connectiq-sdk-*' | sort -V | tail -n 1
  else
    find "$SDKS_DIR" -maxdepth 1 -type d -name 'connectiq-sdk-*' | sort | tail -n 1
  fi
}

annotate_build_output() {
  local DEVICE="$1"
  local LINE

  while IFS= read -r LINE || [[ -n "$LINE" ]]; do
    if [[ "$LINE" == "BUILD SUCCESSFUL" ]]; then
      printf 'BUILD SUCCESSFUL (%s)\n' "$DEVICE"
    else
      printf '%s\n' "$LINE"
    fi
  done
}

LATEST_SDK_ROOT="$(find_latest_sdk_bin)"
LATEST_SDK_BIN="${LATEST_SDK_ROOT:+$LATEST_SDK_ROOT/bin}"
SDK_BIN="${CONNECTIQ_SDK_BIN:-${LATEST_SDK_BIN:-$FALLBACK_SDK_BIN}}"
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}"
KEY_PATH="${CONNECTIQ_DEVELOPER_KEY:-$ROOT_DIR/developer_key.der}"

if [[ ! -x "$SDK_BIN/monkeyc" ]]; then
  echo "monkeyc not found at $SDK_BIN/monkeyc" >&2
  exit 1
fi

if [[ ! -x "$JAVA_HOME/bin/java" ]]; then
  echo "Java not found at $JAVA_HOME/bin/java" >&2
  exit 1
fi

if [[ ! -f "$KEY_PATH" ]]; then
  TMP_KEY="$ROOT_DIR/developer_key.pem"
  openssl genrsa -out "$TMP_KEY" 4096
  openssl pkcs8 -topk8 -inform PEM -outform DER -in "$TMP_KEY" -out "$KEY_PATH" -nocrypt
  rm "$TMP_KEY"
fi

mkdir -p "$ROOT_DIR/bin"

export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

if [[ "$#" -gt 0 ]]; then
  DEVICES=("$@")
else
  DEVICES=()
  while IFS= read -r DEVICE; do
    DEVICES+=("$DEVICE")
  done < <(sed -n 's/.*<iq:product id="\([^"]*\)".*/\1/p' "$ROOT_DIR/manifest.xml")
fi

for DEVICE in "${DEVICES[@]}"; do
  "$SDK_BIN/monkeyc" \
    -f "$ROOT_DIR/monkey.jungle" \
    -d "$DEVICE" \
    -o "$ROOT_DIR/bin/RiseCue-$DEVICE.prg" \
    -y "$KEY_PATH" \
    -w | annotate_build_output "$DEVICE"
done
