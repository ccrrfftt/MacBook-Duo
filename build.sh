#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
APP_DIR="$PROJECT_DIR/MacBook Duo.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

mkdir -p "$MACOS_DIR"
mkdir -p "$CONTENTS_DIR/Resources"
cp "$PROJECT_DIR/Assets/MacBookDuo.icns" "$CONTENTS_DIR/Resources/"
cp "$PROJECT_DIR/Assets/MacBookDuo.png" "$CONTENTS_DIR/Resources/"
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"

swiftc \
  -target arm64-apple-macos15.0 \
  -parse-as-library \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  -framework IOKit \
  -framework QuartzCore \
  -framework MetalKit \
  -framework ScreenCaptureKit \
  -framework Carbon \
  -framework Security \
  -o "$MACOS_DIR/HingeGlass" \
  "$PROJECT_DIR"/Sources/*.swift

zsh "$PROJECT_DIR/test.sh"
# Finder may decorate the generated bundle; this metadata prevents signing.
# Keep security attributes (including quarantine) intact.
if xattr -p com.apple.FinderInfo "$APP_DIR" >/dev/null 2>&1; then
  xattr -d com.apple.FinderInfo "$APP_DIR"
fi
codesign --force --deep --sign "${SIGNING_IDENTITY:--}" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Built: $APP_DIR"
