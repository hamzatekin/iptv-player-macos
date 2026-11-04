#!/bin/sh
# Launches the debug build fresh (no window restoration: a bare binary launch after a force quit
# can restore zero windows) with the .env login (used only while no login is saved in the Keychain),
# and follows its log.
set -e
cd "$(dirname "$0")/.."
if [ -f .env ]; then set -a; . ./.env; set +a; fi
# Outside ~/Documents: the sandboxed app may not write a log there (open fails with -10810).
LOG="${TMPDIR:-/tmp}/iptvplayer-run.log"
: > "$LOG"
pkill -x IPTVPlayer 2>/dev/null || true
open -F -n --stdout "$LOG" --stderr "$LOG" \
  --env IPTV_SERVER="${IPTV_SERVER:-}" --env IPTV_USERNAME="${IPTV_USERNAME:-}" \
  --env IPTV_PASSWORD="${IPTV_PASSWORD:-}" --env IPTV_MPV_LOG="${IPTV_MPV_LOG:-warn}" \
  .build/xcode/Build/Products/Debug/IPTVPlayer.app
echo "Logging to $LOG (Ctrl-C stops following; the app keeps running)"
tail -f "$LOG"
