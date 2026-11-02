#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="DaveTheTrainer"
BUNDLE_ID="${DAVE_TRAINER_BUNDLE_ID:-com.github.davethetrainer.DaveTheTrainer}"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${DAVE_TRAINER_VERSION:-0.1.5}"
APP_BUILD_VERSION="${DAVE_TRAINER_BUILD_VERSION:-6}"
MANIFEST_SCHEMA_VERSION="1.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GIT_COMMIT="${DAVE_TRAINER_GIT_COMMIT:-$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD)}"
BUILD_DATE="${DAVE_TRAINER_BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_ZIP_FILE_NAME="$APP_NAME-v$APP_VERSION-macOS.zip"
APP_ZIP="$DIST_DIR/$APP_ZIP_FILE_NAME"
APP_SHA256="$APP_ZIP.sha256"
DEFAULT_LOCAL_APP_DIR="${HOME:?HOME is required}/Applications"
LOCAL_APP_DIR="${DAVE_TRAINER_LOCAL_APP_DIR:-$DEFAULT_LOCAL_APP_DIR}"
LOCAL_APP_BUNDLE="$LOCAL_APP_DIR/$APP_NAME.app"
STAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/davetrainer-release-stage.XXXXXX")"
ZIP_VERIFY_DIR=""
STAGE_BUNDLE="$STAGE_DIR/$APP_NAME.app"
APP_CONTENTS="$STAGE_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Assets/AppIcon/DaveTheTrainer.icns"
APP_ICON_NAME="DaveTheTrainer"
APP_ENTITLEMENTS="$ROOT_DIR/Assets/Entitlements/DaveTheTrainer.entitlements"
METADATA_SETTLE_SECONDS="1"
IS_RELEASE_PACKAGE=0

cleanup() {
  rm -rf "$STAGE_DIR"
  if [[ "$ZIP_VERIFY_DIR" != "" ]]; then
    rm -rf "$ZIP_VERIFY_DIR"
  fi
}

trap cleanup EXIT

case "$MODE" in
  --release-package|release-package)
    IS_RELEASE_PACKAGE=1
    ;;
esac

clean_bundle_metadata() {
  local bundle_path="$1"
  /usr/bin/xattr -cr "$bundle_path" 2>/dev/null || true
  /usr/bin/xattr -c "$bundle_path" 2>/dev/null || true
  /usr/bin/xattr -dr com.apple.quarantine "$bundle_path" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.FinderInfo "$bundle_path" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.ResourceFork "$bundle_path" 2>/dev/null || true
  /usr/bin/xattr -dr com.apple.FinderInfo "$bundle_path" 2>/dev/null || true
  /usr/bin/xattr -dr com.apple.ResourceFork "$bundle_path" 2>/dev/null || true
  /usr/bin/find "$bundle_path" -exec /usr/bin/xattr -c {} \; 2>/dev/null || true
  /usr/bin/SetFile -a b "$bundle_path" 2>/dev/null || true
  /usr/bin/find "$bundle_path" \( -name "._*" -o -name ".DS_Store" \) -delete
}

resolve_sign_identity() {
  if [[ "${DAVE_TRAINER_SIGN_IDENTITY:-}" != "" ]]; then
    printf '%s\n' "$DAVE_TRAINER_SIGN_IDENTITY"
    return
  fi

  if [[ "$IS_RELEASE_PACKAGE" == "1" ]]; then
    echo "DAVE_TRAINER_SIGN_IDENTITY is required for release packages" >&2
    exit 2
  fi

  local identities
  identities="$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null || true)"

  local developer_id
  developer_id="$(printf '%s\n' "$identities" | /usr/bin/awk -F '"' '/Developer ID Application:/ { print $2; exit }')"
  if [[ "$developer_id" != "" ]]; then
    printf '%s\n' "$developer_id"
    return
  fi

  printf '%s\n' "-"
}

sign_and_verify_bundle() {
  local bundle_path="$1"
  clean_bundle_metadata "$bundle_path"
  /usr/bin/codesign --force --deep --options runtime --entitlements "$APP_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$bundle_path"
  sleep "$METADATA_SETTLE_SECONDS"
  clean_bundle_metadata "$bundle_path"
  /usr/bin/codesign --verify --deep --strict "$bundle_path"
}

copy_signed_app() {
  local source_bundle="$1"
  local target_bundle="$2"
  local target_dir
  target_dir="$(dirname "$target_bundle")"

  mkdir -p "$target_dir"
  rm -rf "$target_bundle"
  /usr/bin/ditto --norsrc "$source_bundle" "$target_bundle"
  sleep "$METADATA_SETTLE_SECONDS"
  sign_and_verify_bundle "$target_bundle"
}

copy_icloud_dist_app() {
  mkdir -p "$DIST_DIR"
  rm -rf "$APP_BUNDLE"
  /usr/bin/ditto --norsrc "$LOCAL_APP_BUNDLE" "$APP_BUNDLE"
  sleep "$METADATA_SETTLE_SECONDS"
  clean_bundle_metadata "$APP_BUNDLE"
}

create_project_zip() {
  mkdir -p "$DIST_DIR"
  rm -f "$APP_ZIP"
  COPYFILE_DISABLE=1 /usr/bin/ditto --norsrc -c -k --keepParent "$LOCAL_APP_BUNDLE" "$APP_ZIP"
}

verify_project_zip() {
  if zipinfo -1 "$APP_ZIP" | /usr/bin/grep -E '(^|/)\._|\.DS_Store'; then
    echo "release zip contains AppleDouble or .DS_Store metadata: $APP_ZIP" >&2
    exit 1
  fi

  ZIP_VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/davetrainer-release-verify.XXXXXX")"
  /usr/bin/ditto -x -k "$APP_ZIP" "$ZIP_VERIFY_DIR"
  /usr/bin/codesign --verify --deep --strict "$ZIP_VERIFY_DIR/$APP_NAME.app"
}

create_project_checksum() {
  (
    cd "$DIST_DIR"
    /usr/bin/shasum -a 256 "$APP_ZIP_FILE_NAME" >"$(basename "$APP_SHA256")"
    /usr/bin/shasum -a 256 -c "$(basename "$APP_SHA256")"
  )
}

SIGN_IDENTITY="$(resolve_sign_identity)"
echo "Signing identity: $SIGN_IDENTITY" >&2

if pgrep -x "$APP_NAME" >/dev/null; then
  if ! pkill -x "$APP_NAME"; then
    echo "warning: failed to stop existing $APP_NAME; close it manually or run with administrator privileges" >&2
  fi
fi

if [[ "$IS_RELEASE_PACKAGE" == "1" ]]; then
  swift build -c release
  BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"
else
  swift build
  BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
fi

rm -rf "$STAGE_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$APP_ICON_SOURCE" "$APP_RESOURCES/$APP_ICON_NAME.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_ICON_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD_VERSION</string>
  <key>DaveTrainerManifestSchemaVersion</key>
  <string>$MANIFEST_SCHEMA_VERSION</string>
  <key>DaveTrainerGitCommit</key>
  <string>$GIT_COMMIT</string>
  <key>DaveTrainerBuildDate</key>
  <string>$BUILD_DATE</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

sleep "$METADATA_SETTLE_SECONDS"
sign_and_verify_bundle "$STAGE_BUNDLE"
copy_signed_app "$STAGE_BUNDLE" "$LOCAL_APP_BUNDLE"
copy_icloud_dist_app
create_project_zip
verify_project_zip
create_project_checksum

open_app() {
  /usr/bin/open -n "$LOCAL_APP_BUNDLE"
}

case "$MODE" in
  --package|package)
    echo "$LOCAL_APP_BUNDLE"
    ;;
  --release-package|release-package)
    echo "$APP_ZIP"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    /usr/bin/codesign --verify --deep --strict "$LOCAL_APP_BUNDLE"
    test -d "$APP_BUNDLE"
    test -f "$APP_ZIP"
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--package|--release-package|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
