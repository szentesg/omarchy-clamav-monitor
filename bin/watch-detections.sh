#!/bin/bash
# Watches ClamAV's on-access log for new " FOUND" lines and appends a
# timestamped copy to a user-owned detections log. clamonacc's own --log
# output has no per-line timestamp, so this is what gives the bar widget
# (and the user) a date/time per detection.
set -uo pipefail

SRC_LOG="/var/log/clamav/clamonacc.log"
OUT_LOG="$HOME/.local/state/omarchy/clamav-detections.log"

mkdir -p "$(dirname "$OUT_LOG")"
touch "$OUT_LOG"

# -F: follow by name (survives log rotation/recreation). -n0: only new lines
# from this point on, not the whole existing file.
tail -F -n0 "$SRC_LOG" 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    *" FOUND")
      printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line" >> "$OUT_LOG"
      ;;
  esac
done
