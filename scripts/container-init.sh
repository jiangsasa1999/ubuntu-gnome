#!/usr/bin/env bash
# ============================================================
# container-init.sh — Ubuntu GNOME 桌面容器初始化脚本
# 在 gdm3 启动前执行, 配置:
#   - 设备权限 (DRM, 输入, 音频)
#   - 用户密码
#   - 家目录初始化
#   - 时区
# ============================================================
set -Eeuo pipefail

readonly DESKTOP_USER="jiang"
readonly DESKTOP_HOME="/home/${DESKTOP_USER}"

log() {
    printf '[container-init] %s\n' "$*"
}

# ---------- 将桌面用户加入宿主机设备组 ----------
add_device_groups() {
    local node gid group_name

    for node in /dev/dri/* /dev/snd/* /dev/input/*; do
        [ -e "$node" ] || continue
        gid="$(stat -c '%g' "$node")"
        [ "$gid" -ne 0 ] || continue

        group_name="$(getent group "$gid" | cut -d: -f1 || true)"
        if [ -z "$group_name" ]; then
            group_name="hostdev-${gid}"
            groupadd --gid "$gid" "$group_name"
        fi
        usermod -aG "$group_name" "$DESKTOP_USER"
    done
}

# ---------- 隐藏更新通知 ----------
disable_update_ui() {
    local applications_dir autostart_dir

    applications_dir="${DESKTOP_HOME}/.local/share/applications"
    autostart_dir="${DESKTOP_HOME}/.config/autostart"
    install -d -m 0755 -o "$DESKTOP_USER" -g "$DESKTOP_USER" \
        "$applications_dir" "$autostart_dir"

    printf '[Desktop Entry]\nHidden=true\n' > "${applications_dir}/update-manager.desktop"
    printf '[Desktop Entry]\nHidden=true\n' > "${autostart_dir}/update-notifier.desktop"
    chown "$DESKTOP_USER:$DESKTOP_USER" \
        "${applications_dir}/update-manager.desktop" \
        "${autostart_dir}/update-notifier.desktop"
    chmod 0644 \
        "${applications_dir}/update-manager.desktop" \
        "${autostart_dir}/update-notifier.desktop"
}

# ---------- 初始化家目录 ----------
seed_home() {
    local marker
    marker="${DESKTOP_HOME}/.container-home-initialized"

    if [ ! -e "$marker" ]; then
        # 从 /etc/skel 复制默认配置
        cp -a -n /etc/skel/. "$DESKTOP_HOME"/
        touch "$marker"
        chown -R "$DESKTOP_USER:$DESKTOP_USER" "$DESKTOP_HOME"
    fi

    # 用户头像
    if [ -f /usr/local/share/avatar.png ]; then
        install -m 0644 -o "$DESKTOP_USER" -g "$DESKTOP_USER" \
            /usr/local/share/avatar.png "${DESKTOP_HOME}/.face"
    fi
}


# ---------- 蓝牙自动连接脚本与 autostart 条目 ----------
setup_bt_autoconnect() {
    local autostart_dir="${DESKTOP_HOME}/.config/autostart"
    install -d -m 0755 -o "$DESKTOP_USER" -g "$DESKTOP_USER" "$autostart_dir"
    if [ -f /usr/local/sbin/bt-autoconnect.sh ]; then
        cat > "${autostart_dir}/bt-autoconnect.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Bluetooth Auto Connect
Exec=/usr/local/sbin/bt-autoconnect.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
EOF
        chmod 0644 "${autostart_dir}/bt-autoconnect.desktop"
        chown "$DESKTOP_USER:$DESKTOP_USER" "${autostart_dir}/bt-autoconnect.desktop"
        log "BT autoconnect entry installed"
    fi
}


# ============================================================
# 主流程
# ============================================================

log "Starting container initialization..."

# 检查硬件
if ! compgen -G '/dev/dri/card*' >/dev/null; then
    log 'ERROR: 没有检测到 /dev/dri/card* — DRM/KMS 无法启动'
    log '提示: 容器需要 privileged 模式, 且宿主机需要有显卡驱动'
    exit 1
fi

if [ ! -d /dev/input ]; then
    log 'WARNING: /dev/input 不存在 — 键盘鼠标将无法工作'
fi

if [ ! -d /dev/snd ]; then
    log 'WARNING: /dev/snd 不存在 — HDMI 音频将不可用'
fi

# 时区
if [ -n "${TZ:-}" ] && [ -e "/usr/share/zoneinfo/${TZ}" ]; then
    ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime
    printf '%s\n' "$TZ" > /etc/timezone
    log "Timezone set to ${TZ}"
fi

# 设置用户密码
printf '%s:%s\n' "$DESKTOP_USER" "${USER_PASSWORD:-ubuntu}" | chpasswd
log "User password configured"

# 初始化家目录
install -d -m 0755 -o "$DESKTOP_USER" -g "$DESKTOP_USER" "$DESKTOP_HOME"
seed_home

# 设备权限
add_device_groups

# 隐藏更新提示
disable_update_ui
setup_bt_autoconnect

# ---------- 配置蓝牙 ----------
configure_bluetooth() {
    log "Configuring Bluetooth..."

    # 确保 bluetooth 组存在
    getent group bluetooth || groupadd -r bluetooth

    # 将桌面用户加入 bluetooth 组
    usermod -aG bluetooth "$DESKTOP_USER" 2>/dev/null || true

    # 确保 bluetoothd 正在运行, 否则 bluetoothctl 会卡住
    if ! pidof bluetoothd >/dev/null 2>&1; then
        log "bluetoothd not running, skipping bluetoothctl commands"
        return 0
    fi

    log "Bluetooth configured"
}

# ----------- 配置代理 -----------
configure_proxy() {
    log "Configuring proxy..."

    if [ -n "${HTTP_PROXY:-}" ]; then
        cat > /etc/environment << EOF
HTTP_PROXY=${HTTP_PROXY}
HTTPS_PROXY=${HTTPS_PROXY}
http_proxy=${HTTP_PROXY}
https_proxy=${HTTPS_PROXY}
no_proxy=${NO_PROXY:-localhost,127.0.0.1,private}
NO_PROXY=${NO_PROXY:-localhost,127.0.0.1,private}
GTK_IM_MODULE=ibus
QT_IM_MODULE=ibus
XMODIFIERS=@im=ibus
EOF

        printf 'Acquire::http::Proxy "%s";\nAcquire::https::Proxy "%s";\n' \
            "$HTTP_PROXY" \
            "$HTTPS_PROXY" > /etc/apt/apt.conf.d/95proxies

        # 设置 GNOME 桌面代理（登录后生效）
        local gnome_autostart="${DESKTOP_HOME}/.config/autostart"
        install -d -m 0755 -o "$DESKTOP_USER" -g "$DESKTOP_USER" "$gnome_autostart"
        cat > "${gnome_autostart}/setup-gnome-proxy.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Setup GNOME Proxy
Exec=/usr/local/sbin/setup-gnome-proxy.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=3
EOF
        chmod 0644 "${gnome_autostart}/setup-gnome-proxy.desktop"
        chown "$DESKTOP_USER:$DESKTOP_USER" "${gnome_autostart}/setup-gnome-proxy.desktop"

        log "Proxy configured (${HTTP_PROXY})"
    else
        log "Proxy not configured (no HTTP_PROXY set)"
    fi
}
configure_proxy
configure_bluetooth

log "DRM devices: $(printf '%s ' /dev/dri/card* 2>/dev/null || echo 'none')"
log "Input devices: $(ls /dev/input/ 2>/dev/null | wc -l) found"
log "Sound devices: $(ls /dev/snd/ 2>/dev/null | wc -l) found"
log 'Container initialization complete!'
