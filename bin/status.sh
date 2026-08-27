#!/bin/bash
# Prints ClamAV status as JSON for the io.github.szentesg.clamav-monitor bar widget.
set -uo pipefail

DETECTIONS_LOG="$HOME/.local/state/omarchy/clamav-detections.log"
DB="/var/lib/clamav/daily.cvd"
# Records the last time any recent detection's file was still present on
# disk, so the urgent bar icon can stay lit for a grace period after the
# file is removed/quarantined instead of flipping the instant it's gone.
LAST_ACTIVE_FILE="$HOME/.local/state/omarchy/clamav-last-active.epoch"
CLEAR_AFTER_SEC=600

last_update_epoch=$(stat -c %Y "$DB" 2>/dev/null || echo 0)
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

now_epoch=$(date +%s)
if (( active_count > 0 )); then
  mkdir -p "$(dirname "$LAST_ACTIVE_FILE")" 2>/dev/null
  echo "$now_epoch" > "$LAST_ACTIVE_FILE" 2>/dev/null
fi

last_active_epoch=0
if [[ -r $LAST_ACTIVE_FILE ]]; then
  last_active_epoch=$(<"$LAST_ACTIVE_FILE")
  [[ $last_active_epoch =~ ^[0-9]+$ ]] || last_active_epoch=0
fi

icon_urgent=false
if (( active_count > 0 )); then
  icon_urgent=true
elif (( last_active_epoch > 0 && now_epoch - last_active_epoch < CLEAR_AFTER_SEC )); then
  icon_urgent=true
fi

jq -cn \
  --argjson lastUpdateEpoch "$last_update_epoch" \
  --argjson clamdActive "$clamd_bool" \
  --argjson clamonaccActive "$clamonacc_bool" \
  --argjson freshclamActive "$freshclam_bool" \
  --argjson total "$total" \
  --argjson activeCount "$active_count" \
  --argjson iconUrgent "$icon_urgent" \
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
    iconUrgent: $iconUrgent,
    recent: $recent,
    logPath: $logPath,
    logReadable: $logReadable
  }' | head -c "$MAX_OUTPUT_BYTES"
