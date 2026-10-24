#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CodexLoginManager"
BUNDLE_ID="io.github.xiaohei210509.CodexLoginManager"
MIN_SYSTEM_VERSION="14.0"
APP_VERSION="${APP_VERSION:-1.0.0}"
APP_BUILD="${APP_BUILD:-1}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
BUILD_ARCHS="${BUILD_ARCHS:-native}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icns"
BUILD_SCRATCH_DIR="${BUILD_SCRATCH_DIR:-${TMPDIR:-/tmp/}${APP_NAME}-build-${BUILD_CONFIGURATION}-${BUILD_ARCHS}}"

if [[ ! "$APP_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  echo "APP_VERSION must contain one to three dot-separated integers (for example 1.0.0)." >&2
  exit 2
fi

if [[ ! "$APP_BUILD" =~ ^[1-9][0-9]*$ ]]; then
  echo "APP_BUILD must be a positive integer." >&2
  exit 2
fi

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

SWIFT_BUILD_ARGS=(
  --scratch-path "$BUILD_SCRATCH_DIR"
  --disable-index-store
  -j 1
  -c "$BUILD_CONFIGURATION"
)

case "$BUILD_ARCHS" in
  native)
    ;;
  universal)
    SWIFT_BUILD_ARGS+=(--arch arm64 --arch x86_64)
    ;;
  *)
    IFS=',' read -r -a REQUESTED_ARCHS <<<"$BUILD_ARCHS"
    for arch in "${REQUESTED_ARCHS[@]}"; do
      SWIFT_BUILD_ARGS+=(--arch "$arch")
    done
    ;;
esac

swift build "${SWIFT_BUILD_ARGS[@]}"
BUILD_BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"
RESOURCE_BUNDLE_SOURCE="$BUILD_BIN_DIR/$RESOURCE_BUNDLE_NAME"

if [[ ! -d "$RESOURCE_BUNDLE_SOURCE" ]]; then
  RESOURCE_BUNDLE_SOURCE="$(find "$BUILD_SCRATCH_DIR" -type d -name "$RESOURCE_BUNDLE_NAME" -print -quit)"
fi

if [[ -z "$RESOURCE_BUNDLE_SOURCE" || ! -d "$RESOURCE_BUNDLE_SOURCE" ]]; then
  echo "Required localization resource bundle was not produced: $RESOURCE_BUNDLE_NAME" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp -X "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp -X "$ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
/usr/bin/ditto "$RESOURCE_BUNDLE_SOURCE" "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME"

for localization in en zh-Hans; do
  localization_file="$(find "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME" \
    -type f -ipath "*/$localization.lproj/Localizable.strings" -print -quit)"
  if [[ -z "$localization_file" ]]; then
    echo "Required localization is missing from the app bundle: $localization" >&2
    exit 1
  fi
done

if [[ ! -f "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME/Contents/Resources/dictation-recipe.json" \
   && ! -f "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME/dictation-recipe.json" ]]; then
  echo "Required embedded dictation recipe is missing from the app bundle." >&2
  exit 1
fi

for embedded_resource in acorn.js dictation-locator.js Acorn-LICENSE.txt; do
  if [[ -z "$(find "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME" -type f -name "$embedded_resource" -print -quit)" ]]; then
    echo "Required adaptive patch resource is missing: $embedded_resource" >&2
    exit 1
  fi
done

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
  <string>Codex Login Manager</string>
  <key>CFBundleDisplayName</key>
  <string>Codex Login Manager</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
  </array>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/plutil -lint "$INFO_PLIST" >/dev/null
# FileProvider can attach Finder metadata that strict code signing rejects.
/usr/bin/xattr -cr "$APP_BUNDLE"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --deep --sign "$CODE_SIGN_IDENTITY" --options runtime --timestamp "$APP_BUNDLE"
else
  /usr/bin/codesign --force --deep --sign - --timestamp=none "$APP_BUNDLE"
fi
/usr/bin/xattr -cr "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build|build)
    echo "Built: $APP_BUNDLE ($APP_VERSION, $BUILD_CONFIGURATION, $BUILD_ARCHS)"
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
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    /usr/bin/xattr -cr "$APP_BUNDLE"
    /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
    ;;
  *)
    echo "usage: $0 [run|--build|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
