#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
INSTALLED_APP="/Applications/MacBook Duo.app"
MODE="${1:-run}"
BUILD_REQUESTED=true

case "$MODE" in
  --relaunch|--relaunch-diagnostics) BUILD_REQUESTED=false ;;
  run|--verify|--diagnostics) ;;
  *) print -u2 "usage: $0 [run|--verify|--diagnostics|--relaunch|--relaunch-diagnostics]"; exit 2 ;;
esac

if [[ "$BUILD_REQUESTED" == true ]]; then
  zsh "$PROJECT_DIR/build.sh"
  APP_DIR=$(< "$PROJECT_DIR/.build/app-path.txt")
else
  codesign --verify --deep --strict "$INSTALLED_APP"
fi
# Only replace the installed app after its replacement has built and passed checks.
if [[ "$BUILD_REQUESTED" == true && -d "$INSTALLED_APP" ]]; then
  mkdir -p "$PROJECT_DIR/.build/backups"
  BACKUP="$PROJECT_DIR/.build/backups/MacBook-Duo-$(date +%Y%m%d-%H%M%S).zip"
  ditto -c -k --sequesterRsrc --keepParent "$INSTALLED_APP" "$BACKUP"
fi
pkill -TERM -f '/MacBook Duo[.]app/Contents/MacOS/HingeGlass' || true
for attempt in {1..30}; do
  pgrep -f '/MacBook Duo[.]app/Contents/MacOS/HingeGlass' >/dev/null || break
  sleep 0.1
done
if pgrep -f '/MacBook Duo[.]app/Contents/MacOS/HingeGlass' >/dev/null; then
  print -u2 "MacBook Duo is still running; installation was cancelled."
  exit 1
fi
if [[ "$BUILD_REQUESTED" == true ]]; then
  ditto "$APP_DIR" "$INSTALLED_APP"
fi
codesign --verify --deep --strict "$INSTALLED_APP"
if [[ "$MODE" == "--diagnostics" || "$MODE" == "--relaunch-diagnostics" ]]; then
  /usr/bin/open -n "$INSTALLED_APP" --args --diagnostics
else
  /usr/bin/open -n "$INSTALLED_APP"
fi
if [[ "$MODE" == "--verify" ]]; then
  sleep 1
  pgrep -f '/MacBook Duo[.]app/Contents/MacOS/HingeGlass' >/dev/null
  print "Verified: MacBook Duo is running"
fi
