#!/usr/bin/env bash
#
# lib/desktop.sh - Optional desktop environment installation
#

# Install desktop environment based on config
install_desktop() {
    if [[ "$INSTALL_DESKTOP" != "yes" ]]; then
        log_info "Desktop installation skipped"
        return
    fi

    log_info "Installing desktop environment: $DESKTOP_ENV"

    # Install display server first
    install_display_server

    # Install selected DE
    case "$DESKTOP_ENV" in
        gnome)
            install_gnome
            ;;
        kde)
            install_kde
            ;;
        xfce)
            install_xfce
            ;;
        hyprland)
            install_hyprland
            ;;
        sway)
            install_sway
            ;;
        none)
            log_info "No desktop environment selected"
            ;;
        *)
            die "Unknown desktop environment: $DESKTOP_ENV"
            ;;
    esac

    # Install common desktop packages
    install_desktop_common

    log_info "Desktop installation complete"
}

# Install display server
install_display_server() {
    case "$DISPLAY_SERVER" in
        x11)
            install_x11
            ;;
        wayland)
            install_wayland
            ;;
        auto)
            if [[ "$DESKTOP_ENV" == "sway" || "$DESKTOP_ENV" == "hyprland" ]]; then
                install_wayland
            else
                install_x11
                install_wayland
            fi
            ;;
        none)
            log_info "Skipping display server"
            ;;
    esac
}

# Install X11
install_x11() {
    log_info "Installing X11"
    chroot_run "emerge --ask=n x11-base/xorg-server x11-apps/xinit x11-drivers/xf86-input-libinput"
}

# Install Wayland
install_wayland() {
    log_info "Installing Wayland"
    chroot_run "emerge --ask=n dev-libs/wayland gui-libs/wlroots"
}

# Install GNOME
install_gnome() {
    log_info "Installing GNOME"
    chroot_run "emerge --ask=n gnome-base/gnome"

    case "$INIT_SYSTEM" in
        systemd)
            chroot_run "systemctl enable gdm"
            ;;
        openrc)
            chroot_run "rc-update add gdm default"
            ;;
    esac
}

# Install KDE Plasma
install_kde() {
    log_info "Installing KDE Plasma"
    chroot_run "emerge --ask=n kde-plasma/plasma-meta kde-apps/kde-apps-meta"

    case "$INIT_SYSTEM" in
        systemd)
            chroot_run "systemctl enable sddm"
            ;;
        openrc)
            chroot_run "rc-update add xdm default"
            echo "DISPLAYMANAGER=\"sddm\"" | chroot_run "tee -a /etc/conf.d/xdm"
            ;;
    esac
}

# Install XFCE
install_xfce() {
    log_info "Installing XFCE"
    chroot_run "emerge --ask=n xfce-base/xfce4-meta xfce-extra/xfce4-goodies"

    case "$INIT_SYSTEM" in
        systemd)
            chroot_run "systemctl enable lightdm"
            ;;
        openrc)
            chroot_run "rc-update add xdm default"
            echo "DISPLAYMANAGER=\"lightdm\"" | chroot_run "tee -a /etc/conf.d/xdm"
            ;;
    esac
}

# Install Hyprland (Wayland compositor)
install_hyprland() {
    log_info "Installing Hyprland"

    if [[ "$HYPRLAND_USE_OVERLAY" == "yes" ]]; then
        chroot_run "emerge --ask=n app-eselect/eselect-repository"
        chroot_run "eselect repository enable hyproverlay" || {
            log_warn "hyproverlay not in repos list, adding manually"
            chroot_run "eselect repository add hyproverlay git https://codeberg.org/hyproverlay/hyproverlay.git"
        }
        chroot_run "emaint sync -r hyproverlay"
        chroot_run "mkdir -p /etc/portage/package.accept_keywords"
        chroot_run "echo '*/*::hyproverlay' >> /etc/portage/package.accept_keywords/hyproverlay"
        log_info "Added hyproverlay overlay (wiki recommended method)"
    else
        local masked
        masked=$(chroot_run "emerge --pretend gui-wm/hyprland 2>&1" | grep -c "masked by" || true)
        if [[ "$masked" -gt 0 ]]; then
            die "Hyprland is masked. Enable hyproverlay overlay via HYPRLAND_USE_OVERLAY=yes"
        fi
    fi

    chroot_run "emerge --ask=n gui-wm/hyprland"

    log_info "Installing xdg-desktop-portal for screen sharing"
    chroot_run "emerge --ask=n gui-libs/xdg-desktop-portal-hyprland" 2>/dev/null || true

    # Install display manager
    case "$HYPRLAND_DM" in
        greetd)
            log_info "Installing greetd"
            chroot_run "emerge --ask=n gui-libs/greetd"
            chroot_run "mkdir -p /etc/greetd"
            chroot_run "cat > /etc/greetd/config.toml << 'EOF'
[terminal]
vt = 1

[default_session]
command = start-hyprland
user = greetd
EOF"
            case "$INIT_SYSTEM" in
                systemd)
                    chroot_run "systemctl enable greetd"
                    ;;
                openrc)
                    chroot_run "rc-update add greetd default"
                    ;;
            esac
            ;;
        sddm)
            log_info "Installing SDDM"
            chroot_run "emerge --ask=n kde-plasma/sddm"
            case "$INIT_SYSTEM" in
                systemd)
                    chroot_run "systemctl enable sddm"
                    ;;
                openrc)
                    chroot_run "rc-update add xdm default"
                    chroot_run "echo \"DISPLAYMANAGER=\\\"sddm\\\"\" >> /etc/conf.d/xdm"
                    ;;
            esac
            ;;
        none)
            log_info "No display manager for Hyprland"
            ;;
    esac

    log_info "Hyprland installed (configure via ~/.config/hypr/hyprland.conf)"
}

# Install Sway (Wayland tiling WM)
install_sway() {
    log_info "Installing Sway"
    chroot_run "emerge --ask=s wayland"
    chroot_run "emerge --ask=s gui-wm/sway"

    log_info "Sway installed (configure via ~/.config/sway/config)"
}

# Install common desktop packages
install_desktop_common() {
    log_info "Installing common desktop packages"

    local packages="media-fonts/dejavu media-fonts/noto media-sound/pipewire \
                    net-misc/networkmanager app-editors/vim app-arch/file-roller \
                    x11-terms/alacritty www-client/firefox"

    chroot_run "emerge --ask=n ${packages}" || {
        log_warn "Some desktop packages failed to install"
    }
}

# Setup laptop-specific power management
setup_laptop_power() {
    if [[ "$PLATFORM" != "laptop" ]]; then
        return
    fi

    log_info "Setting up laptop power management"

    # Install power management tools
    chroot_run "emerge --ask=n sys-power/tlp sys-power/cpupower sys-power/powertop \
                sys-firmware/intel-microcode sys-firmware/linux-firmware"

    case "$INIT_SYSTEM" in
        openrc)
            chroot_run "rc-update add tlp default"
            chroot_run "rc-update add cpupower default"
            ;;
        systemd)
            chroot_run "systemctl enable tlp"
            chroot_run "systemctl enable cpupower"
            ;;
    esac

    # Enable thermald if available
    chroot_run "emerge --ask=n sys-power/thermald" 2>/dev/null || true
    chroot_run "emerge --ask=n sys-power/acpid" 2>/dev/null || true

    case "$INIT_SYSTEM" in
        openrc)
            chroot_run "rc-update add thermald default" 2>/dev/null || true
            chroot_run "rc-update add acpid default" 2>/dev/null || true
            ;;
        systemd)
            chroot_run "systemctl enable thermald" 2>/dev/null || true
            chroot_run "systemctl enable acpid" 2>/dev/null || true
            ;;
    esac

    log_info "Laptop power management configured"
}

# Full desktop setup
setup_desktop() {
    install_desktop
    setup_laptop_power
}
