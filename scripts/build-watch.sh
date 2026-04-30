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

cleanup_public_token_build() {
  if [[ -n "${PUBLIC_BUILD_DIR:-}" ]]; then
    rm -rf "$PUBLIC_BUILD_DIR"
  fi
}

should_create_build_config_override_files() {
  [[ "${RISECUE_EMBED_PUBLIC_ENDPOINT_TOKEN:-}" == "1" \
    || -n "${RISECUE_APP_BUILD_VERSION+x}" \
    || -n "${RISECUE_SHOW_BUILD_VERSION+x}" ]]
}

create_build_config_override_files() {
  local PUBLIC_ENDPOINT_TOKEN=""
  local PUBLIC_SOURCE_DIR
  local PUBLIC_SOURCE_FILE
  local PUBLIC_JUNGLE_FILE

  if [[ "${RISECUE_EMBED_PUBLIC_ENDPOINT_TOKEN:-}" == "1" ]]; then
    PUBLIC_ENDPOINT_TOKEN="${RISECUE_PUBLIC_ENDPOINT_TOKEN:-${ENDPOINT_TOKEN:-}}"

    if [[ -z "$PUBLIC_ENDPOINT_TOKEN" ]]; then
      echo "Public watch build requires RISECUE_PUBLIC_ENDPOINT_TOKEN or ENDPOINT_TOKEN." >&2
      exit 1
    fi
  fi

  if ! command -v node >/dev/null 2>&1; then
    echo "node is required to generate watch build config overrides." >&2
    exit 1
  fi

  PUBLIC_BUILD_DIR="$(mktemp -d "$ROOT_DIR/bin/public-watch-build.XXXXXX")"
  PUBLIC_SOURCE_DIR="$PUBLIC_BUILD_DIR/source"
  PUBLIC_SOURCE_FILE="$PUBLIC_SOURCE_DIR/RiseCueBuildConfigOverride.mc"
  PUBLIC_JUNGLE_FILE="$PUBLIC_BUILD_DIR/build-config.jungle"

  mkdir -p "$PUBLIC_SOURCE_DIR"

  PUBLIC_ENDPOINT_TOKEN="$PUBLIC_ENDPOINT_TOKEN" \
    APP_BUILD_VERSION="${RISECUE_APP_BUILD_VERSION-}" \
    APP_BUILD_VERSION_IS_SET="${RISECUE_APP_BUILD_VERSION+x}" \
    SHOW_BUILD_VERSION="${RISECUE_SHOW_BUILD_VERSION-}" \
    SHOW_BUILD_VERSION_IS_SET="${RISECUE_SHOW_BUILD_VERSION+x}" \
    node - "$PUBLIC_SOURCE_FILE" "$ROOT_DIR/source/RiseCueBuildConfig.mc" <<'NODE'
const fs = require('fs');

const outputPath = process.argv[2];
const defaultConfigPath = process.argv[3];
const token = process.env.PUBLIC_ENDPOINT_TOKEN || '';
const defaultConfig = fs.readFileSync(defaultConfigPath, 'utf8');

function readDefaultString(name) {
  const match = defaultConfig.match(new RegExp(`const\\s+${name}\\s*=\\s*"((?:\\\\.|[^"\\\\])*)";`));

  if (!match) {
    return '';
  }

  try {
    return JSON.parse(`"${match[1]}"`);
  } catch {
    return match[1];
  }
}

function readDefaultBoolean(name) {
  const match = defaultConfig.match(new RegExp(`const\\s+${name}\\s*=\\s*(true|false);`));
  return match ? match[1] === 'true' : false;
}

function parseBooleanFlag(value) {
  const normalized = value.trim().toLowerCase();

  if (['1', 'true', 'yes', 'on'].includes(normalized)) {
    return true;
  }

  if (['0', 'false', 'no', 'off'].includes(normalized)) {
    return false;
  }

  console.error('RISECUE_SHOW_BUILD_VERSION must be true or false.');
  process.exit(1);
}

function assertNoControlCharacters(value, label) {
  if (/[\x00-\x1f\x7f]/.test(value)) {
    console.error(`${label} must not contain control characters.`);
    process.exit(1);
  }
}

function escapeMonkeyString(value) {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

const appBuildVersion = process.env.APP_BUILD_VERSION_IS_SET
  ? process.env.APP_BUILD_VERSION
  : readDefaultString('APP_BUILD_VERSION');
const showBuildVersion = process.env.SHOW_BUILD_VERSION_IS_SET
  ? parseBooleanFlag(process.env.SHOW_BUILD_VERSION || '')
  : readDefaultBoolean('SHOW_BUILD_VERSION');

assertNoControlCharacters(token, 'Public endpoint token');
assertNoControlCharacters(appBuildVersion, 'App build version');

const source = `(:background)
module RiseCueBuildConfig {
    function getAppBuildVersion() {
        return "${escapeMonkeyString(appBuildVersion)}";
    }

    function shouldShowBuildVersion() {
        return ${showBuildVersion ? 'true' : 'false'};
    }

    function getPublicEndpointToken() {
        return "${escapeMonkeyString(token)}";
    }
}
`;

fs.writeFileSync(outputPath, source, 'utf8');
NODE

  printf 'base.sourcePath = $(base.sourcePath);"%s"\n' "$PUBLIC_SOURCE_DIR" > "$PUBLIC_JUNGLE_FILE"
  printf 'base.excludeAnnotations = defaultBuildConfig\n' >> "$PUBLIC_JUNGLE_FILE"

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
  TMP_KEY="$ROOT_DIR/developer_key.pem"
  openssl genrsa -out "$TMP_KEY" 4096
  openssl pkcs8 -topk8 -inform PEM -outform DER -in "$TMP_KEY" -out "$KEY_PATH" -nocrypt
  rm "$TMP_KEY"
fi

mkdir -p "$ROOT_DIR/bin"

if should_create_build_config_override_files; then
  trap cleanup_public_token_build EXIT
  create_build_config_override_files
fi

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
    -f "$JUNGLE_FILES" \
    -d "$DEVICE" \
    -o "$ROOT_DIR/bin/RiseCue-$DEVICE.prg" \
    -y "$KEY_PATH" \
    -w | annotate_build_output "$DEVICE"
done
