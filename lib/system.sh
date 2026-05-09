#!/usr/bin/env bash
#
# lib/system.sh - Bootloader, fstab, hostname, network, timezone
#

# Configure hostname
configure_hostname() {
    log_info "Setting hostname: $HOSTNAME"
    chroot_run "echo '${HOSTNAME}' > /etc/hostname"
    chroot_run "echo '127.0.0.1 ${HOSTNAME}.localhost ${HOSTNAME}' >> /etc/hosts"
    chroot_run "echo '::1 ${HOSTNAME}.localhost ${HOSTNAME}' >> /etc/hosts"
}

# Configure timezone
configure_timezone() {
    log_info "Setting timezone: $TIMEZONE"
    chroot_run "ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime"
}

# Configure locale
configure_locale() {
    log_info "Setting locale: $LOCALE"

    local lang="${LOCALE%%.*}"
    local charset="${LOCALE#*.}"

    chroot_run "echo '${LOCALE} UTF-8' > /etc/locale.gen"
    chroot_run "locale-gen"
    chroot_run "eselect locale set ${LOCALE}"
}

# Generate fstab
generate_fstab() {
    local disk="$1"
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    local fstab="${root}/etc/fstab"

    log_info "Generating fstab"

    local boot_part="/dev/${disk}2"
    local root_part="/dev/${disk}3"
    local root_fs="${ROOT_FS}"

    # Get optimized mount options
    local root_opts
    root_opts=$(get_fs_mount_opts "$root_fs" "$PLATFORM")

    cat > "$fstab" << FSTAB
# <fs>                  <mountpoint>    <type>  <opts>          <dump/pass>
${root_part}            /               ${root_fs}  ${root_opts}      0 1
${boot_part}            /boot           ext4    noauto,noatime  0 2
FSTAB

    if is_uefi; then
        local efi_part="/dev/${disk}1"
        echo "${efi_part}           /boot/efi       vfat    defaults,noatime  0 2" >> "$fstab"
    fi

    # Swap (if configured)
    echo "" >> "$fstab"
    echo "# Swap (add if needed)" >> "$fstab"
    echo "/dev/${disk}4            none            swap    sw              0 0" >> "$fstab"

    log_info "fstab generated"
}

# Configure network
configure_network() {
    log_info "Configuring network"

    case "$INIT_SYSTEM" in
        openrc)
            configure_network_openrc
            ;;
        systemd)
            configure_network_systemd
            ;;
    esac
}

# Configure network for OpenRC
configure_network_openrc() {
    log_info "Setting up OpenRC network"
    chroot_run "rc-update add dhcpcd default" || true
    chroot_run "rc-update add NetworkManager default" 2>/dev/null || true
}

# Configure network for systemd
configure_network_systemd() {
    log_info "Setting up systemd-networkd"
    chroot_run "systemctl enable systemd-networkd"
    chroot_run "systemctl enable systemd-resolved"
}

# Install and configure bootloader
install_bootloader() {
    case "$BOOTLOADER" in
        grub)
            install_grub
            ;;
        systemd-boot)
            install_systemd_boot
            ;;
        none)
            log_info "Skipping bootloader installation"
            ;;
        *)
            die "Unknown bootloader: $BOOTLOADER"
            ;;
    esac
}

# Install GRUB
install_grub() {
    local disk="$1"

    log_info "Installing GRUB"

    # Install GRUB package
    chroot_run "emerge --ask=n sys-boot/grub:2" || die "Failed to install GRUB"

    if is_uefi; then
        # UEFI GRUB
        chroot_run "grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo" || \
            chroot_run "grub-install --target=arm64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo"
    else
        # BIOS GRUB
        chroot_run "grub-install --target=i386-pc /dev/${disk}"
    fi

    # Generate config
    chroot_run "grub-mkconfig -o /boot/grub/grub.cfg"

    log_info "GRUB installed"
}

# Install systemd-boot
install_systemd_boot() {
    if ! is_uefi; then
        die "systemd-boot requires UEFI"
    fi

    log_info "Installing systemd-boot"
    chroot_run "bootctl install"

    # Create boot entry
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    local entry_dir="${root}/boot/loader/entries"
    ensure_dir "$entry_dir"

    local root_part="/dev/${disk}3"
    local root_uuid
    root_uuid=$(blkid -s UUID -o value "$root_part")

    cat > "${entry_dir}/gentoo.conf" << ENTRY
title Gentoo Linux
linux /vmlinuz
initrd /initramfs
options root=UUID=${root_uuid} rootfstype=${ROOT_FS} rw
ENTRY

    cat > "${root}/boot/loader/loader.conf" << LOADER
default gentoo.conf
timeout 3
LOADER

    log_info "systemd-boot installed"
}

# Set root password
set_root_password() {
    if [[ -n "$ROOT_PASSWORD" ]]; then
        log_info "Setting root password"
        chroot_run "echo 'root:${ROOT_PASSWORD}' | chpasswd"
    else
        log_warn "No root password set, you will need to set one manually"
    fi
}

# Create additional users
create_extra_users() {
    if [[ -z "$EXTRA_USERS" ]]; then
        return
    fi

    for user in $EXTRA_USERS; do
        log_info "Creating user: $user"
        chroot_run "useradd -m -G wheel,audio,video,users -s /bin/bash ${user}" || {
            log_warn "Failed to create user: $user"
        }
        chroot_run "echo '${user} ALL=(ALL:ALL) ALL' >> /etc/sudoers"
    done
}

# Set default shell
set_default_shell() {
    chroot_run "emerge --ask=n app-shells/bash"
    chroot_run "chsh -s /bin/bash root" 2>/dev/null || true
}

# Full system configuration
configure_system() {
    local disk="$1"

    configure_hostname
    configure_timezone
    configure_locale
    generate_fstab "$disk"
    configure_network
    install_bootloader "$disk"
    set_root_password
    create_extra_users
    set_default_shell

    log_info "System configuration complete"
}
