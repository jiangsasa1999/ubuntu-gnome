#!/usr/bin/env bash
MARKER="${HOME}/.gnome-proxy-configured"
if [ -f "$MARKER" ]; then
    exit 0
fi
if [ -n "${HTTP_PROXY:-}" ] && [ -n "${HTTPS_PROXY:-}" ]; then
    HTTP_HOST=$(echo "$HTTP_PROXY" | awk -F[/:] '{print $4}')
    HTTP_PORT=$(echo "$HTTP_PROXY" | awk -F[/:] '{print $5}')
    HTTPS_HOST=$(echo "$HTTPS_PROXY" | awk -F[/:] '{print $4}')
    HTTPS_PORT=$(echo "$HTTPS_PROXY" | awk -F[/:] '{print $5}')
    gsettings set org.gnome.system.proxy mode manual 2>/dev/null || true
    gsettings set org.gnome.system.proxy.http host "${HTTP_HOST}" 2>/dev/null || true
    gsettings set org.gnome.system.proxy.http port "${HTTP_PORT}" 2>/dev/null || true
    gsettings set org.gnome.system.proxy.https host "${HTTPS_HOST}" 2>/dev/null || true
    gsettings set org.gnome.system.proxy.https port "${HTTPS_PORT}" 2>/dev/null || true
    gsettings set org.gnome.system.proxy ignore-hosts "['localhost', '127.0.0.0/8', '::1', '192.168.1.0/24']" 2>/dev/null || true
    touch "$MARKER"
fi
