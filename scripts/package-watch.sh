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
  echo "Developer key not found at $KEY_PATH. Run npm run build:watch once or set CONNECTIQ_DEVELOPER_KEY." >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/bin"

export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

"$SDK_BIN/monkeyc" \
  -f "$ROOT_DIR/monkey.jungle" \
  -e \
  -o "$ROOT_DIR/bin/RiseCue.iq" \
  -y "$KEY_PATH" \
  -w
