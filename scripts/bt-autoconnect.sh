#!/usr/bin/env bash
# 用户登录后自动连接已配对的蓝牙音频设备
# 由 ~/.config/autostart/bt-autoconnect.desktop 触发
set -Eeuo pipefail

log() {
    echo "[bt-autoconnect] $*"
}

# 等待 bluetoothd 就绪（最多 10 秒）
for i in $(seq 1 10); do
    if pidof bluetoothd >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if ! pidof bluetoothd >/dev/null 2>&1; then
    log "bluetoothd not available, giving up"
    exit 1
fi

log "Scanning for audio devices..."
bluetoothctl devices 2>/dev/null | while read -r _ mac rest; do
    [ -n "$mac" ] || continue
    info="$(bluetoothctl info "$mac" 2>/dev/null)"
    # 只连接音频设备（Audio Sink / Audio Source）
    echo "$info" | grep -q "Audio Sink\|Audio Source" || continue
    if echo "$info" | grep -q "Connected: yes"; then
        log "$mac already connected"
        continue
    fi
    log "Connecting $mac..."
    timeout 10 bluetoothctl connect "$mac" >/dev/null 2>&1 || true
done
log "Auto-connect done"
