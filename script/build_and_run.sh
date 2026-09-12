#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/MacBook Duo.app"
MODE="${1:-run}"

case "$MODE" in
  run|--verify) ;;
  *) print -u2 "usage: $0 [run|--verify]"; exit 2 ;;
esac

# Match this app's executable path, including an installed copy of the same app.
pkill -TERM -f '/MacBook Duo[.]app/Contents/MacOS/HingeGlass' || true
zsh "$PROJECT_DIR/build.sh"
/usr/bin/open -n "$APP_DIR"
if [[ "$MODE" == "--verify" ]]; then
  sleep 1
  pgrep -f '/MacBook Duo[.]app/Contents/MacOS/HingeGlass' >/dev/null
  print "Verified: MacBook Duo is running"
fi
