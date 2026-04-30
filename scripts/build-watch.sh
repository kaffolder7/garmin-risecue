#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CONNECTIQ_SDKS_DIR="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"

find_latest_sdk_root() {
  local SDKS_DIR="${CONNECTIQ_SDKS_DIR:-$DEFAULT_CONNECTIQ_SDKS_DIR}"

  if [[ ! -d "$SDKS_DIR" ]]; then
    return 0
  fi

  if sort -V </dev/null >/dev/null 2>&1; then
    find "$SDKS_DIR" -maxdepth 1 -type d -name 'connectiq-sdk-*' | sort -V | tail -n 1
  else
    find "$SDKS_DIR" -maxdepth 1 -type d -name 'connectiq-sdk-*' | sort | tail -n 1
  fi
}

normalize_sdk_bin() {
  local SDK_PATH="$1"

  if [[ -x "$SDK_PATH/monkeyc" ]]; then
    printf '%s\n' "$SDK_PATH"
  elif [[ -x "$SDK_PATH/bin/monkeyc" ]]; then
    printf '%s\n' "$SDK_PATH/bin"
  else
    printf '%s\n' "$SDK_PATH"
  fi
}

resolve_sdk_bin() {
  local SDK_ROOT

  if [[ -n "${CONNECTIQ_SDK_BIN:-}" ]]; then
    normalize_sdk_bin "$CONNECTIQ_SDK_BIN"
    return 0
  fi

  SDK_ROOT="$(find_latest_sdk_root)"
  if [[ -n "$SDK_ROOT" ]]; then
    printf '%s/bin\n' "$SDK_ROOT"
  fi

  return 0
}

print_sdk_failure() {
  local SDK_BIN="$1"

  if [[ -n "$SDK_BIN" ]]; then
    echo "monkeyc not found at $SDK_BIN/monkeyc." >&2
  else
    echo "Connect IQ SDK not found." >&2
  fi

  if [[ -n "${CONNECTIQ_SDK_BIN:-}" ]]; then
    echo "CONNECTIQ_SDK_BIN is set to: $CONNECTIQ_SDK_BIN" >&2
    echo "Set CONNECTIQ_SDK_BIN to the Connect IQ SDK bin directory that contains monkeyc." >&2
  else
    echo "Set CONNECTIQ_SDK_BIN to the Connect IQ SDK bin directory that contains monkeyc." >&2
    echo "If SDK Manager stores SDKs somewhere else, set CONNECTIQ_SDKS_DIR to the directory containing connectiq-sdk-* folders." >&2
  fi
}

resolve_java_home() {
  local JAVA_BIN
  local JAVA_BIN_DIR
  local RESOLVED_JAVA_BIN

  if [[ -n "${JAVA_HOME:-}" ]]; then
    printf '%s\n' "$JAVA_HOME"
    return 0
  fi

  if [[ -x /usr/libexec/java_home ]]; then
    if /usr/libexec/java_home >/dev/null 2>&1; then
      /usr/libexec/java_home
      return 0
    fi
  fi

  if command -v java >/dev/null 2>&1; then
    JAVA_BIN="$(command -v java)"
    if command -v readlink >/dev/null 2>&1; then
      if RESOLVED_JAVA_BIN="$(readlink -f "$JAVA_BIN" 2>/dev/null)" && [[ -n "$RESOLVED_JAVA_BIN" ]]; then
        JAVA_BIN="$RESOLVED_JAVA_BIN"
      fi
    fi

    JAVA_BIN_DIR="$(cd "$(dirname "$JAVA_BIN")" && pwd)"
    cd "$JAVA_BIN_DIR/.." && pwd
  fi

  return 0
}

print_java_failure() {
  if [[ -n "${JAVA_HOME:-}" ]]; then
    echo "Java not found at $JAVA_HOME/bin/java." >&2
    echo "Set JAVA_HOME to a JDK or JRE directory whose bin/java is executable." >&2
  else
    echo "Java not found." >&2
    echo "Set JAVA_HOME to a JDK or JRE directory whose bin/java is executable, or put java on PATH." >&2
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

SDK_BIN="$(resolve_sdk_bin)"
RESOLVED_JAVA_HOME="$(resolve_java_home)"
JAVA_BIN="${RESOLVED_JAVA_HOME:+$RESOLVED_JAVA_HOME/bin/java}"
KEY_PATH="${CONNECTIQ_DEVELOPER_KEY:-$ROOT_DIR/developer_key.der}"

if [[ ! -x "$SDK_BIN/monkeyc" ]]; then
  print_sdk_failure "$SDK_BIN"
  exit 1
fi

if [[ -z "$RESOLVED_JAVA_HOME" || ! -x "$JAVA_BIN" ]]; then
  print_java_failure
  exit 1
fi

if ! "$JAVA_BIN" -version >/dev/null 2>&1; then
  echo "Java at $JAVA_BIN could not run." >&2
  echo "Set JAVA_HOME to a working JDK or JRE directory whose bin/java is executable." >&2
  exit 1
fi

if [[ ! -f "$KEY_PATH" ]]; then
  TMP_KEY="$ROOT_DIR/developer_key.pem"
  openssl genrsa -out "$TMP_KEY" 4096
  openssl pkcs8 -topk8 -inform PEM -outform DER -in "$TMP_KEY" -out "$KEY_PATH" -nocrypt
  rm "$TMP_KEY"
fi

mkdir -p "$ROOT_DIR/bin"

JAVA_HOME="$RESOLVED_JAVA_HOME"
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
