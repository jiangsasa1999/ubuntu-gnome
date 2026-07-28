#!/usr/bin/env bash
# ============================================================
# set-resolution.sh — 设置 HDMI 显示分辨率和刷新率
# 使用方式 (在容器内):
#   sudo set-resolution.sh              # 查看当前显示设备
#   sudo set-resolution.sh 1920x1080    # 设置分辨率 (60Hz)
#   sudo set-resolution.sh 1920x1080@60 # 指定刷新率
#   sudo set-resolution.sh 3840x2160@30 # 4K 30Hz
# ============================================================
set -Eeuo pipefail

log() { printf '[set-resolution] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

# ---------- 检测显示后端 ----------
detect_backend() {
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        echo "wayland"
    elif [ -n "${DISPLAY:-}" ]; then
        echo "x11"
    else
        # 尝试自动检测
        if [ -S /run/user/1000/wayland-0 ] || [ -S /run/user/1000/wayland-1 ]; then
            echo "wayland"
        elif command -v xrandr &>/dev/null && xrandr &>/dev/null 2>&1; then
            echo "x11"
        else
            echo "unknown"
        fi
    fi
}

# ---------- Wayland 下使用 wlr-randr ----------
wayland_set_resolution() {
    local output target="$1"

    if ! command -v wlr-randr &>/dev/null; then
        log "wlr-randr 未安装, 尝试安装..."
        apt-get update -qq && apt-get install -y -qq wlr-randr 2>/dev/null || true
    fi

    if ! command -v wlr-randr &>/dev/null; then
        die "需要安装 wlr-randr: apt-get install wlr-randr"
    fi

    # 列出可用输出
    log "可用显示设备:"
    wlr-randr 2>/dev/null || die "无法获取显示设备列表"

    # 如果没有指定完整模式, 尝试解析
    if [[ "$target" =~ ^[0-9]+x[0-9]+(@[0-9]+)?$ ]]; then
        # 自动选择第一个非 off 的输出
        output=$(wlr-randr 2>/dev/null | grep -v "^ " | head -1 | awk '{print $1}')
        [ -z "$output" ] && die "没有检测到显示输出"

        log "设置 $output 为 ${target}..."
        if [[ "$target" == *@* ]]; then
            wlr-randr --output "$output" --mode "${target//@/ }"
        else
            # 尝试以 60Hz 的常见刷新率
            for rate in 60.00 59.94 50.00 30.00 24.00; do
                if wlr-randr --output "$output" --mode "${target}@${rate}" 2>/dev/null; then
                    log "已设置 ${target}@${rate}"
                    return 0
                fi
            done
            die "无法设置分辨率 ${target}, 请检查可用模式"
        fi
    else
        # 用户直接传了完整的 wlr-randr 参数
        wlr-randr "$@"
    fi
}

# ---------- X11 下使用 xrandr ----------
x11_set_resolution() {
    local target="$1"

    if ! command -v xrandr &>/dev/null; then
        log "xrandr 未安装, 尝试安装..."
        apt-get update -qq && apt-get install -y -qq x11-xserver-utils 2>/dev/null || true
    fi

    if ! command -v xrandr &>/dev/null; then
        die "需要安装 xrandr: apt-get install x11-xserver-utils"
    fi

    log "可用显示设备:"
    xrandr --current 2>/dev/null | grep " connected" || die "没有检测到显示器"

    local output
    output=$(xrandr --current 2>/dev/null | grep " connected" | head -1 | awk '{print $1}')
    [ -z "$output" ] && die "没有检测到显示输出"

    log "设置 $output 为 ${target}..."
    if [[ "$target" == *@* ]]; then
        local res="${target%%@*}"
        local rate="${target#*@}"
        xrandr --output "$output" --mode "$res" --rate "$rate" || \
            die "无法设置 ${target}, 请检查可用模式"
    else
        xrandr --output "$output" --mode "$target" || \
            die "无法设置 ${target}, 请检查可用模式"
    fi
    log "已设置 ${target}"
}

# ============================================================
# 主流程
# ============================================================
BACKEND=$(detect_backend)
log "检测到显示后端: ${BACKEND}"

case "${1:-list}" in
    list)
        log "查询当前显示状态..."
        case "$BACKEND" in
            wayland)
                exec wlr-randr 2>/dev/null || die "wlr-randr 不可用"
                ;;
            x11)
                exec xrandr --current 2>/dev/null || die "xrandr 不可用"
                ;;
            *)
                die "无法检测显示后端 (Wayland 或 X11)"
                ;;
        esac
        ;;
    --help|-h)
        echo "用法: $0 [分辨率]"
        echo "示例:"
        echo "  $0 list            # 列出当前显示状态"
        echo "  $0                 # 同上"
        echo "  $0 1920x1080       # 设置 1080p 60Hz"
        echo "  $0 1920x1080@60    # 设置 1080p 60Hz (显式)"
        echo "  $0 3840x2160@30    # 设置 4K 30Hz"
        echo "  $0 1280x720@50     # 设置 720p 50Hz"
        ;;
    *)
        case "$BACKEND" in
            wayland)
                wayland_set_resolution "$@"
                ;;
            x11)
                x11_set_resolution "$@"
                ;;
            *)
                die "无法检测显示后端"
                ;;
        esac
        ;;
esac
