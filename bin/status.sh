#!/bin/bash
# Prints ClamAV status as JSON for the io.github.szentesg.clamav-monitor bar widget.
set -uo pipefail

DETECTIONS_LOG="$HOME/.local/state/omarchy/clamav-detections.log"
DB="/var/lib/clamav/daily.cvd"

last_update_epoch=$(stat -c %Y "$DB" 2>/dev/null || echo 0)
clamd_active=$(systemctl is-active clamav-daemon.service 2>/dev/null)
clamonacc_active=$(systemctl is-active clamav-clamonacc.service 2>/dev/null)
freshclam_active=$(systemctl is-active clamav-freshclam.service 2>/dev/null)

[[ $clamd_active == active ]] && clamd_bool=true || clamd_bool=false
[[ $clamonacc_active == active ]] && clamonacc_bool=true || clamonacc_bool=false
[[ $freshclam_active == active ]] && freshclam_bool=true || freshclam_bool=false

# Each line: "YYYY-MM-DD HH:MM:SS <path>: <signature> FOUND"
found_lines=()
if [[ -r $DETECTIONS_LOG ]]; then
  while IFS= read -r line; do
    found_lines+=("$line")
  done < "$DETECTIONS_LOG"
fi
total=${#found_lines[@]}

recent_json="[]"
if (( total > 0 )); then
  start=$(( total > 10 ? total - 10 : 0 ))
  entries=()
  for ((i = total - 1; i >= start; i--)); do
    line="${found_lines[$i]}"
    when="${line:0:19}"
    rest="${line:20}"
    when_epoch=$(date -d "$when" +%s 2>/dev/null || echo 0)
    path=$(sed -E 's/^(.*): (.*) FOUND$/\1/' <<<"$rest")
    sig=$(sed -E 's/^(.*): (.*) FOUND$/\2/' <<<"$rest")
    entries+=("$(jq -cn --arg path "$path" --arg sig "$sig" --argjson whenEpoch "$when_epoch" '{path:$path, signature:$sig, whenEpoch:$whenEpoch}')")
  done
  recent_json=$(printf '%s\n' "${entries[@]}" | jq -cs '.')
fi

jq -cn \
  --argjson lastUpdateEpoch "$last_update_epoch" \
  --argjson clamdActive "$clamd_bool" \
  --argjson clamonaccActive "$clamonacc_bool" \
  --argjson freshclamActive "$freshclam_bool" \
  --argjson total "$total" \
  --arg logPath "$DETECTIONS_LOG" \
  --argjson recent "$recent_json" \
  --argjson logReadable "$([[ -r $DETECTIONS_LOG ]] && echo true || echo false)" \
  '{
    lastUpdateEpoch: $lastUpdateEpoch,
    clamdActive: $clamdActive,
    clamonaccActive: $clamonaccActive,
    freshclamActive: $freshclamActive,
    total: $total,
    recent: $recent,
    logPath: $logPath,
    logReadable: $logReadable
  }'
