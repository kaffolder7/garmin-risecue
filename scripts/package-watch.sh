#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CONNECTIQ_SDKS_DIR="$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"
DEFAULT_CONNECTIQ_DEVICES_DIR="$HOME/Library/Application Support/Garmin/ConnectIQ/Devices"

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

annotate_package_output() {
  local LINE
  local BUILT_COUNT
  local DEVICE_INDEX
  local PACKAGE_TARGET

  while IFS= read -r LINE || [[ -n "$LINE" ]]; do
    if [[ "$LINE" =~ ^([0-9]+)[[:space:]]+OUT[[:space:]]+OF[[:space:]]+([0-9]+)[[:space:]]+DEVICES[[:space:]]+BUILT$ ]]; then
      BUILT_COUNT="${BASH_REMATCH[1]}"
      PACKAGE_TARGET="package target metadata unavailable"

      if (( BUILT_COUNT == 0 )); then
        PACKAGE_TARGET="starting package build"
      elif (( BUILT_COUNT <= ${#PACKAGE_TARGETS[@]} )); then
        DEVICE_INDEX=$((BUILT_COUNT - 1))
        PACKAGE_TARGET="${PACKAGE_TARGETS[$DEVICE_INDEX]}"
      fi

      printf '%s (%s)\n' "$LINE" "$PACKAGE_TARGET"
    else
      printf '%s\n' "$LINE"
    fi
  done
}

find_devices_dir() {
  if [[ -n "${CONNECTIQ_DEVICES_DIR:-}" ]]; then
    printf '%s\n' "$CONNECTIQ_DEVICES_DIR"
  elif [[ -d "$DEFAULT_CONNECTIQ_DEVICES_DIR" ]]; then
    printf '%s\n' "$DEFAULT_CONNECTIQ_DEVICES_DIR"
  fi

  return 0
}

load_package_targets() {
  local DEVICES_DIR

  DEVICES_DIR="$(find_devices_dir)"

  if [[ -z "$DEVICES_DIR" || ! -d "$DEVICES_DIR" ]] || ! command -v node >/dev/null 2>&1; then
    sed -n 's/.*<iq:product id="\([^"]*\)".*/\1/p' "$ROOT_DIR/manifest.xml"
    return
  fi

  DEVICES_DIR="$DEVICES_DIR" node - "$ROOT_DIR/manifest.xml" <<'NODE'
const fs = require('fs');
const path = require('path');

const manifestPath = process.argv[2];
const devicesDir = process.env.DEVICES_DIR;
const manifest = fs.readFileSync(manifestPath, 'utf8');
const devices = [...manifest.matchAll(/<iq:product\s+id="([^"]+)"/g)].map((match) => match[1]);

for (const device of devices) {
  const compilerPath = path.join(devicesDir, device, 'compiler.json');

  try {
    const compiler = JSON.parse(fs.readFileSync(compilerPath, 'utf8'));
    const partNumbers = Array.isArray(compiler.partNumbers)
      ? compiler.partNumbers.map((partNumber) => partNumber.number).filter(Boolean)
      : [];

    if (partNumbers.length > 0) {
      for (const partNumber of partNumbers) {
        console.log(`${device} / ${partNumber}`);
      }
    } else {
      console.log(device);
    }
  } catch {
    console.log(device);
  }
}
NODE
}

cleanup_public_token_build() {
  if [[ -n "${PUBLIC_BUILD_DIR:-}" ]]; then
    rm -rf "$PUBLIC_BUILD_DIR"
  fi
}

create_public_token_build_files() {
  local PUBLIC_ENDPOINT_TOKEN="${RISECUE_PUBLIC_ENDPOINT_TOKEN:-${ENDPOINT_TOKEN:-}}"
  local PUBLIC_SOURCE_DIR
  local PUBLIC_SOURCE_FILE
  local PUBLIC_JUNGLE_FILE

  if [[ -z "$PUBLIC_ENDPOINT_TOKEN" ]]; then
    echo "Public watch package requires RISECUE_PUBLIC_ENDPOINT_TOKEN or ENDPOINT_TOKEN." >&2
    exit 1
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo "node is required to generate public watch build config." >&2
    exit 1
  fi

  PUBLIC_BUILD_DIR="$(mktemp -d "$ROOT_DIR/bin/public-watch-build.XXXXXX")"
  PUBLIC_SOURCE_DIR="$PUBLIC_BUILD_DIR/source"
  PUBLIC_SOURCE_FILE="$PUBLIC_SOURCE_DIR/RiseCueBuildConfigPublic.mc"
  PUBLIC_JUNGLE_FILE="$PUBLIC_BUILD_DIR/public-token.jungle"

  mkdir -p "$PUBLIC_SOURCE_DIR"

  PUBLIC_ENDPOINT_TOKEN="$PUBLIC_ENDPOINT_TOKEN" node - "$PUBLIC_SOURCE_FILE" <<'NODE'
const fs = require('fs');

const outputPath = process.argv[2];
const token = process.env.PUBLIC_ENDPOINT_TOKEN || '';

if (/[\x00-\x1f\x7f]/.test(token)) {
  console.error('Public endpoint token must not contain control characters.');
  process.exit(1);
}

const escapedToken = token.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
const source = `module RiseCueBuildConfig {
    function getPublicEndpointToken() {
        return "${escapedToken}";
    }
}
`;

fs.writeFileSync(outputPath, source, 'utf8');
NODE

  printf 'base.sourcePath = $(base.sourcePath);"%s"\n' "$PUBLIC_SOURCE_DIR" > "$PUBLIC_JUNGLE_FILE"
  printf 'base.excludeAnnotations = defaultPublicEndpointToken\n' >> "$PUBLIC_JUNGLE_FILE"

  JUNGLE_FILES="$ROOT_DIR/monkey.jungle;$PUBLIC_JUNGLE_FILE"
}

SDK_BIN="$(resolve_sdk_bin)"
RESOLVED_JAVA_HOME="$(resolve_java_home)"
JAVA_BIN="${RESOLVED_JAVA_HOME:+$RESOLVED_JAVA_HOME/bin/java}"
KEY_PATH="${CONNECTIQ_DEVELOPER_KEY:-$ROOT_DIR/developer_key.der}"
PUBLIC_BUILD_DIR=""
JUNGLE_FILES="$ROOT_DIR/monkey.jungle"

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
  echo "Developer key not found at $KEY_PATH." >&2
  echo "Run npm run build:watch once to create $ROOT_DIR/developer_key.der, or set CONNECTIQ_DEVELOPER_KEY to an existing developer_key.der file." >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/bin"

if [[ "${RISECUE_EMBED_PUBLIC_ENDPOINT_TOKEN:-}" == "1" ]]; then
  trap cleanup_public_token_build EXIT
  create_public_token_build_files
fi

JAVA_HOME="$RESOLVED_JAVA_HOME"
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

PACKAGE_TARGETS=()
while IFS= read -r PACKAGE_TARGET; do
  PACKAGE_TARGETS+=("$PACKAGE_TARGET")
done < <(load_package_targets)

"$SDK_BIN/monkeyc" \
  -f "$JUNGLE_FILES" \
  -e \
  -o "$ROOT_DIR/bin/RiseCue.iq" \
  -y "$KEY_PATH" \
  -w | annotate_package_output
