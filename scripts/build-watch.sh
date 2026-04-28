#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONNECTIQ_SDK_BIN="$(find "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks" \
  -maxdepth 1 -type d -name 'connectiq-sdk-*' \
  | sort -V \
  | tail -n 1)/bin"
SDK_BIN="${CONNECTIQ_SDK_BIN:-$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-9.1.0-2026-03-09-6a872a80b/bin}"
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
    -w
done
