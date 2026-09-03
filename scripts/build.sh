#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Diff.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"

mkdir -p "$MACOS" "$RESOURCES"

echo "Generating icon…"
"$ROOT/scripts/make-icon.sh" "$RESOURCES/AppIcon.icns"

echo "Compiling Diff…"
# shellcheck disable=SC2207
SOURCES=("${(@f)$(find "$ROOT/Sources" -name '*.swift' | sort)}")

swiftc -O -parse-as-library \
  -target "$TARGET" \
  -sdk "$SDK" \
  -framework SwiftUI \
  -framework AppKit \
  -o "$MACOS/Diff" \
  "${SOURCES[@]}"

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"
echo -n "APPLDiff" > "$CONTENTS/PkgInfo"

codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"
