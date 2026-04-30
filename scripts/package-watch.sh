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

load_package_targets() {
  local DEVICES_DIR="$HOME/Library/Application Support/Garmin/ConnectIQ/Devices"

  if ! command -v node >/dev/null 2>&1; then
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

LATEST_SDK_ROOT="$(find_latest_sdk_bin)"
LATEST_SDK_BIN="${LATEST_SDK_ROOT:+$LATEST_SDK_ROOT/bin}"
SDK_BIN="${CONNECTIQ_SDK_BIN:-${LATEST_SDK_BIN:-$FALLBACK_SDK_BIN}}"
JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21}"
KEY_PATH="${CONNECTIQ_DEVELOPER_KEY:-$ROOT_DIR/developer_key.der}"
PUBLIC_BUILD_DIR=""
JUNGLE_FILES="$ROOT_DIR/monkey.jungle"

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

if [[ "${RISECUE_EMBED_PUBLIC_ENDPOINT_TOKEN:-}" == "1" ]]; then
  trap cleanup_public_token_build EXIT
  create_public_token_build_files
fi

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
