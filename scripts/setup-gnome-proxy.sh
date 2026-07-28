#!/usr/bin/env bash
# 用户登录后设置 GNOME 桌面代理
# 由 ~/.config/autostart/setup-gnome-proxy.desktop 触发

set -Eeuo pipefail

# 等待用户 D-Bus 会话就绪
for i in $(seq 1 10); do
    if pgrep -u "$USER" gnome-session >/dev/null 2>&1 || pgrep -u "$USER" gnome-shell >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "[setup-gnome-proxy] No display available, skipping"
    exit 0
fi

# 从 /etc/environment 读取代理配置
PROXY_HTTP=$(grep -oP 'HTTP_PROXY=\K.*' /etc/environment 2>/dev/null || echo "")
PROXY_HTTPS=$(grep -oP 'HTTPS_PROXY=\K.*' /etc/environment 2>/dev/null || echo "")

if [ -z "$PROXY_HTTP" ]; then
    echo "[setup-gnome-proxy] No proxy configured, skipping"
    exit 0
fi

# 提取 host 和 port
HOST=$(echo "$PROXY_HTTP" | sed -E 's|https?://||' | sed -E 's/:[0-9]+//')
PORT=$(echo "$PROXY_HTTP" | sed -E 's|.*:([0-9]+)$|\1|')

if [ -z "$HOST" ] || [ -z "$PORT" ]; then
    echo "[setup-gnome-proxy] Invalid proxy URL: $PROXY_HTTP"
    exit 1
fi

gsettings set org.gnome.system.proxy mode manual
gsettings set org.gnome.system.proxy.http host "$HOST"
gsettings set org.gnome.system.proxy.http port "$PORT"
gsettings set org.gnome.system.proxy.https host "$HOST"
gsettings set org.gnome.system.proxy.https port "$PORT"
gsettings set org.gnome.system.proxy.ignore-hosts "['localhost', '127.0.0.0/8', '::1', '192.168.1.0/24']"

echo "[setup-gnome-proxy] GNOME proxy set to $HOST:$PORT"
