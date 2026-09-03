#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Diff"
SRC="$ROOT/build/${APP_NAME}.app"
DEST_DIR="${HOME}/Applications"
DEST="$DEST_DIR/${APP_NAME}.app"

was_running=0
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  was_running=1
  echo "Quitting running ${APP_NAME}…"
  osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
  for _ in {1..40}; do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    pkill -x "$APP_NAME" || true
    sleep 0.2
  fi
fi

if [[ -d "$ROOT/.git/hooks" && -f "$ROOT/.githooks/post-commit" ]]; then
  cp "$ROOT/.githooks/post-commit" "$ROOT/.git/hooks/post-commit"
  chmod +x "$ROOT/.git/hooks/post-commit"
fi

echo "Building…"
"$ROOT/scripts/build.sh"

echo "Installing to ${DEST}…"
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
codesign --force --deep --sign - "$DEST" >/dev/null

if [[ "${OPEN_AFTER_INSTALL:-}" == "1" || "$was_running" -eq 1 ]]; then
  echo "Launching ${APP_NAME}…"
  open "$DEST"
fi

echo "Installed ${DEST}"
