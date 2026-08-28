#!/bin/bash
# Watches ClamAV's on-access log for new " FOUND" lines and appends a
# timestamped copy to a user-owned detections log. clamonacc's own --log
# output has no per-line timestamp, so this is what gives the bar widget
# (and the user) a date/time per detection.
set -uo pipefail

SRC_LOG="/var/log/clamav/clamonacc.log"
OUT_LOG="$HOME/.local/state/omarchy/clamav-detections.log"

mkdir -p "$(dirname "$OUT_LOG")"

# The detections log sits at a predictable path in a user-writable directory.
# Anything already there that isn't a plain regular file - a symlink planted
# to redirect our writes into another same-user file, or a FIFO to stall the
# service - is refused rather than written through.
if [[ -L $OUT_LOG || ( -e $OUT_LOG && ! -f $OUT_LOG ) ]]; then
  printf 'clamav-monitor: %s is not a regular file, refusing to use it\n' "$OUT_LOG" >&2
  exit 1
fi

# Create the log (if absent) and append every record through its own
# O_NOFOLLOW open, so a symlink appearing at the path at any point after the
# check above makes that open fail instead of following it elsewhere.
# dd oflag=nofollow gives O_NOFOLLOW, oflag=append gives O_APPEND, and
# conv=notrunc keeps dd from truncating the existing file on open.
umask 077
dd if=/dev/null of="$OUT_LOG" oflag=nofollow conv=notrunc status=none 2>/dev/null || true

append_record() {
  printf '%s\n' "$1" \
    | dd of="$OUT_LOG" oflag=append,nofollow conv=notrunc status=none 2>/dev/null
}

# -F: follow by name (survives log rotation/recreation). -n0: only new lines
# from this point on, not the whole existing file.
tail -F -n0 "$SRC_LOG" 2>/dev/null | while IFS= read -r line; do
  case "$line" in
    *" FOUND")
      append_record "$(date '+%Y-%m-%d %H:%M:%S') $line"
      ;;
  esac
done
