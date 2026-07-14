#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version, for example 1.0.0-beta.1>" >&2
  exit 2
fi

VERSION="${VERSION#v}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
  echo "version must use the supported release syntax (for example 1.0.0 or 1.0.0-beta.1)" >&2
  exit 2
fi

APP_VERSION="${VERSION%%-*}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="CodexLoginManager"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
RELEASE_DIR="$ROOT_DIR/dist/release"
ARCHIVE="$RELEASE_DIR/$APP_NAME-v$VERSION-macOS-universal.zip"
CHECKSUMS="$RELEASE_DIR/SHA256SUMS.txt"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

APP_VERSION="$APP_VERSION" \
APP_BUILD="${APP_BUILD:-1}" \
BUILD_CONFIGURATION=release \
BUILD_ARCHS=universal \
BUILD_SCRATCH_DIR="${BUILD_SCRATCH_DIR:-${TMPDIR:-/tmp/}${APP_NAME}-release-$VERSION}" \
  "$ROOT_DIR/script/build_and_run.sh" --build

/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP_BUNDLE/Contents/Info.plist" | grep -Fx "$APP_VERSION" >/dev/null
/usr/bin/xattr -cr "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
/usr/bin/lipo "$APP_BUNDLE/Contents/MacOS/$APP_NAME" -verify_arch arm64 x86_64
/usr/bin/xattr -cr "$APP_BUNDLE"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"

VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp/}${APP_NAME}-release-verify.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
/usr/bin/ditto -x -k "$ARCHIVE" "$VERIFY_DIR"
ARCHIVED_APP="$VERIFY_DIR/$APP_NAME.app"

/usr/bin/plutil -lint "$ARCHIVED_APP/Contents/Info.plist" >/dev/null
/usr/bin/plutil -extract CFBundleShortVersionString raw "$ARCHIVED_APP/Contents/Info.plist" | grep -Fx "$APP_VERSION" >/dev/null
/usr/bin/plutil -extract CFBundleVersion raw "$ARCHIVED_APP/Contents/Info.plist" | grep -Fx "${APP_BUILD:-1}" >/dev/null
/usr/bin/codesign --verify --deep --strict "$ARCHIVED_APP"
/usr/bin/lipo "$ARCHIVED_APP/Contents/MacOS/$APP_NAME" -verify_arch arm64 x86_64

(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$(basename "$ARCHIVE")" >"$(basename "$CHECKSUMS")"
)

echo "Release archive: $ARCHIVE"
echo "Checksums: $CHECKSUMS"
