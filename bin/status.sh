#!/bin/bash
# Prints ClamAV status as JSON for the io.github.szentesg.clamav-monitor bar widget.
set -uo pipefail

DETECTIONS_LOG="$HOME/.local/state/omarchy/clamav-detections.log"
# freshclam ships the daily database as .cvd, but once it applies an
# incremental diff (which happens on the very first auto-update) it
# converts the file to .cld and the .cvd stops existing. Check both and
# take whichever is newer so this doesn't go stale after the first update.
last_update_epoch=0
for db in /var/lib/clamav/daily.cld /var/lib/clamav/daily.cvd; do
  db_epoch=$(stat -c %Y "$db" 2>/dev/null || echo 0)
  (( db_epoch > last_update_epoch )) && last_update_epoch=$db_epoch
done

clamd_active=$(systemctl is-active clamav-daemon.service 2>/dev/null)
clamonacc_active=$(systemctl is-active clamav-clamonacc.service 2>/dev/null)
freshclam_active=$(systemctl is-active clamav-freshclam.service 2>/dev/null)

[[ $clamd_active == active ]] && clamd_bool=true || clamd_bool=false
[[ $clamonacc_active == active ]] && clamonacc_bool=true || clamonacc_bool=false
[[ $freshclam_active == active ]] && freshclam_bool=true || freshclam_bool=false

# Each line: "YYYY-MM-DD HH:MM:SS <path>: <signature> FOUND"
# Count with wc and take only the last 10 lines with tail so an
# indefinitely growing log is never loaded into memory in full.
#
# Line and field lengths are attacker-controlled (a malicious filename or a
# custom signature), so each one is hard-truncated below. This bounds the
# script's own stdout before it ever reaches Panel.qml's StdioCollector,
# rather than relying solely on that collector's post-hoc byte check.
MAX_LINE_BYTES=4096
MAX_FIELD_BYTES=1024
MAX_OUTPUT_BYTES=65536

total=0
if [[ -r $DETECTIONS_LOG ]]; then
  total=$(wc -l < "$DETECTIONS_LOG")
fi

recent_json="[]"
active_count=0
if (( total > 0 )); then
  entries=()
  while IFS= read -r line; do
    line="${line:0:MAX_LINE_BYTES}"
    when="${line:0:19}"
    rest="${line:20}"
    when_epoch=$(date -d "$when" +%s 2>/dev/null || echo 0)
    path=$(sed -E 's/^(.*): (.*) FOUND$/\1/' <<<"$rest")
    sig=$(sed -E 's/^(.*): (.*) FOUND$/\2/' <<<"$rest")
    # Checked before truncation, on the file path as ClamAV logged it, so a
    # detection whose file was since deleted or quarantined is told apart
    # from one that's still sitting there.
    if [[ -n $path && -e $path ]]; then
      present=true
      (( active_count++ ))
    else
      present=false
    fi
    path="${path:0:MAX_FIELD_BYTES}"
    sig="${sig:0:MAX_FIELD_BYTES}"
    entries+=("$(jq -cn --arg path "$path" --arg sig "$sig" --argjson whenEpoch "$when_epoch" --argjson present "$present" '{path:$path, signature:$sig, whenEpoch:$whenEpoch, present:$present}')")
  done < <(tail -n 10 "$DETECTIONS_LOG" | tac)
  recent_json=$(printf '%s\n' "${entries[@]}" | jq -cs '.')
fi

jq -cn \
  --argjson lastUpdateEpoch "$last_update_epoch" \
  --argjson clamdActive "$clamd_bool" \
  --argjson clamonaccActive "$clamonacc_bool" \
  --argjson freshclamActive "$freshclam_bool" \
  --argjson total "$total" \
  --argjson activeCount "$active_count" \
  --arg logPath "$DETECTIONS_LOG" \
  --argjson recent "$recent_json" \
  --argjson logReadable "$([[ -r $DETECTIONS_LOG ]] && echo true || echo false)" \
  '{
    lastUpdateEpoch: $lastUpdateEpoch,
    clamdActive: $clamdActive,
    clamonaccActive: $clamonaccActive,
    freshclamActive: $freshclamActive,
    total: $total,
    activeCount: $activeCount,
    recent: $recent,
    logPath: $logPath,
    logReadable: $logReadable
  }' | head -c "$MAX_OUTPUT_BYTES"
