# ============================================================
# Ubuntu GNOME Desktop Container — 适用于 FnOS HDMI/DP 输出
# ============================================================
# 构建方式:
#   docker compose build
# 或在项目目录下:
#   docker build -t ubuntu-gnome-desktop .
# ============================================================

# ---------- Base ----------
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

# ---------- Build arguments ----------
ARG DEBIAN_FRONTEND=noninteractive
ARG USER_UID=1000
ARG USER_GID=1000

# ---------- System environment ----------
# container=docker 告诉 systemd 它在容器中运行 (跳过 udev, modprobe 等)
ENV container=docker
ENV TZ=Asia/Shanghai
ENV LANG=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh
ENV LC_ALL=zh_CN.UTF-8

# ============================================================
# 安装系统包
# ============================================================
RUN set -ux; \
    \
    # 阻止 apt 的守护进程在容器内启动 (桌面包的 postinst 常会尝试启动服务)
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; \
    chmod 0755 /usr/sbin/policy-rc.d; \
    \
    apt-get update; \
    \
    # 基础桌面 + 系统组件 (核心依赖, 不装这些根本无法启动)
    apt-get install -y --no-install-recommends \
        ubuntu-desktop-minimal \
        gdm3 \
        dbus-user-session \
        systemd \
        systemd-sysv \
        ; \
    \
    # 显卡/输入/音频 (不同 Ubuntu 版本包名有差异, 用 || true 兜底)
    apt-get install -y --no-install-recommends \
        mesa-utils \
        mesa-va-drivers \
        mesa-vulkan-drivers \
        intel-media-va-driver \
        vainfo \
        libinput-tools \
        pipewire \
        pipewire-pulse \
        pipewire-alsa \
        wireplumber \
        pulseaudio-utils \
        pavucontrol \
        alsa-utils \
        || true; \
    \
    # 桌面应用 (某些在 24.04/26.04 可能不存在)
    apt-get install -y --no-install-recommends \
        nautilus \
        gnome-control-center \
        gnome-text-editor \
        gnome-calculator \
        ptyxis \
        gnome-terminal \
        loupe \
       || true; \
   \
   # 工具和中文化
   apt-get install -y --no-install-recommends \
       ibus \
       ibus-libpinyin \
       bluez \
      blueman \
      gnome-keyring \
      libpam-gnome-keyring \
      sudo curl wget jq ca-certificates \
        pciutils procps psmisc kbd dconf-cli \
        locales \
        language-pack-zh-hans \
        language-pack-gnome-zh-hans \
        fonts-noto-cjk \
        fonts-noto-color-emoji \
        fonts-ubuntu \
       || true; \
   \
   # Google Chrome (通过 dpkg 直接安装 .deb, 避免 gpg tty 问题)
   curl -fsSLo /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb; \
   dpkg -i /tmp/chrome.deb 2>/dev/null || true; \
   apt-get install -f -y --no-install-recommends; \
   rm -f /tmp/chrome.deb; \
   \
   # 生成中文 locale
   locale-gen zh_CN.UTF-8 || true; \
    update-locale LANG=zh_CN.UTF-8 LANGUAGE=zh_CN:zh LC_ALL=zh_CN.UTF-8 || true; \
    \
    rm -f /usr/sbin/policy-rc.d; \
    apt-get clean; \
   rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# ============================================================
# 复制配置文件和脚本
# ============================================================

COPY --chmod=0755 scripts/container-init.sh /usr/local/sbin/container-init.sh
COPY --chmod=0755 scripts/set-resolution.sh /usr/local/sbin/set-resolution.sh
COPY --chmod=0755 scripts/bt-autoconnect.sh /usr/local/sbin/bt-autoconnect.sh

COPY --chmod=0755 scripts/setup-gnome-proxy.sh /usr/local/sbin/setup-gnome-proxy.sh
COPY config/container-init.service /etc/systemd/system/container-init.service
COPY config/gdm-custom.conf /etc/gdm3/custom.conf
COPY config/logind.conf /etc/systemd/logind.conf.d/20-container.conf
COPY config/99disable-periodic-updates /etc/apt/apt.conf.d/99disable-periodic-updates
COPY config/00-hdmi-desktop /etc/dconf/db/local.d/00-hdmi-desktop
COPY config/avatar.png /usr/local/share/avatar.png
COPY config/accountsservice-jiang /usr/local/share/accountsservice-jiang
COPY --chmod=0755 config/setup-gnome-proxy.sh /usr/local/share/setup-gnome-proxy.sh
COPY config/setup-gnome-proxy.desktop /etc/xdg/autostart/setup-gnome-proxy.desktop
COPY config/bluetoothd.service.d/override.conf /etc/systemd/system/bluetooth.service.d/override.conf
COPY config/02-input-sources /etc/dconf/db/local.d/02-input-sources
COPY config/ibus-daemon.desktop /etc/xdg/autostart/ibus-daemon.desktop

# ============================================================
# 系统配置
# ============================================================
RUN set -ux; \
    \
   # 创建桌面用户 jiang (密码在容器启动时通过 container-init.sh 从环境变量设置)
   # 先移除 ubuntu 基础镜像中的默认用户和组 (可能占用 UID/GID 1000)
   id ubuntu 2>/dev/null && userdel -f -r ubuntu || true; \
   getent group ubuntu 2>/dev/null && groupdel ubuntu || true; \
   getent group bluetooth || groupadd -r bluetooth; \
   groupadd --gid ${USER_GID} jiang; \
    useradd --uid ${USER_UID} --gid ${USER_GID} \
        --create-home --home-dir /home/jiang \
        --shell /bin/bash \
        --groups sudo,video,render,input,audio,bluetooth \
        jiang; \
    echo 'jiang:ubuntu' | chpasswd; \
    \
    # 桌面环境下 sudo 弹密码框出不来, 所以免密码
    echo '%sudo ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/nopasswd; \
    \
    # 头像和 AccountsService 配置
    install -d -m 0755 /var/lib/AccountsService/icons /var/lib/AccountsService/users; \
    install -m 0644 /usr/local/share/avatar.png /var/lib/AccountsService/icons/jiang; \
    install -m 0600 /usr/local/share/accountsservice-jiang /var/lib/AccountsService/users/jiang; \
    install -m 0644 -o jiang -g jiang /usr/local/share/avatar.png /home/jiang/.face; \
    \
    # 启用关键服务
    systemctl enable container-init.service || true; \
    systemctl enable gdm3.service || true; \
    systemctl set-default graphical.target || true; \
    \
    # 屏蔽容器里不需要的服务 (单个加 || true 避免某服务不存在导致构建失败)
    systemctl mask getty@tty1.service 2>/dev/null || true; \
    systemctl mask console-getty.service 2>/dev/null || true; \
    systemctl mask NetworkManager.service 2>/dev/null || true; \
    systemctl mask systemd-networkd.service 2>/dev/null || true; \
    systemctl mask systemd-networkd.socket 2>/dev/null || true; \
    systemctl mask systemd-resolved.service 2>/dev/null || true; \
    systemctl mask systemd-timesyncd.service 2>/dev/null || true; \
    systemctl mask systemd-sysctl.service 2>/dev/null || true; \
    systemctl mask systemd-modules-load.service 2>/dev/null || true; \
    systemctl mask systemd-udevd.service 2>/dev/null || true; \
    systemctl mask systemd-udevd-control.socket 2>/dev/null || true; \
    systemctl mask systemd-udevd-kernel.socket 2>/dev/null || true; \
    systemctl mask systemd-udev-trigger.service 2>/dev/null || true; \
    systemctl mask ModemManager.service 2>/dev/null || true; \
    systemctl mask cups.service cups.socket 2>/dev/null || true; \
    systemctl mask fwupd.service 2>/dev/null || true; \
    systemctl mask packagekit.service 2>/dev/null || true; \
    systemctl mask snapd.service snapd.socket 2>/dev/null || true; \
    systemctl mask unattended-upgrades.service 2>/dev/null || true; \
    systemctl mask apt-daily.service apt-daily-upgrade.service 2>/dev/null || true; \
   systemctl mask apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true; \
   systemctl mask power-profiles-daemon.service 2>/dev/null || true; \
   # 屏蔽 firstboot 服务, 避免它在无交互终端时卡住
   systemctl mask systemd-firstboot.service 2>/dev/null || true; \
   \
   # dconf update 在构建时没有 D-Bus, 会报错但不影响
   mkdir -p /etc/dconf/db/local.d; \
   printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/local; \
   printf 'GTK_IM_MODULE=ibus\nQT_IM_MODULE=ibus\nXMODIFIERS=@im=ibus\n' >> /etc/environment; \
   printf 'export GTK_IM_MODULE=ibus\nexport QT_IM_MODULE=ibus\nexport XMODIFIERS=@im=ibus\n' >> /home/jiang/.profile; \
   chown jiang:jiang /home/jiang/.profile; \
   dconf update || true; \
   \
   # 预生成 machine-id, 避免容器首次启动时卡在 firstboot
   systemd-machine-id-setup || true; \
   dbus-uuidgen > /var/lib/dbus/machine-id 2>/dev/null || true

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
