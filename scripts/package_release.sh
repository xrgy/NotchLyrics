#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="NotchLyrics"
VERSION="${1:-0.1.0}"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
RELEASE_DIR="$ROOT_DIR/release"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

cd "$ROOT_DIR"

env CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/clang-module-cache" swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

cp "$ROOT_DIR/packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

mkdir -p "$RELEASE_DIR"
rm -f "$RELEASE_DIR/$APP_NAME-$VERSION-macos-arm64.zip" "$RELEASE_DIR/$APP_NAME-$VERSION-macos-arm64"

cp "$BUILD_DIR/$APP_NAME" "$RELEASE_DIR/$APP_NAME-$VERSION-macos-arm64"
chmod +x "$RELEASE_DIR/$APP_NAME-$VERSION-macos-arm64"

ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$RELEASE_DIR/$APP_NAME-$VERSION-macos-arm64.zip"

echo "Created:"
echo "  $RELEASE_DIR/$APP_NAME-$VERSION-macos-arm64"
echo "  $RELEASE_DIR/$APP_NAME-$VERSION-macos-arm64.zip"
