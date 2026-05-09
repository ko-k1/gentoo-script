#!/usr/bin/env bash
#
# lib/chroot.sh - Chroot setup and mount handling
#

# Mount pseudo-filesystems for chroot
mount_chroot_fs() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    ensure_dir "${root}/proc"
    ensure_dir "${root}/sys"
    ensure_dir "${root}/dev"
    ensure_dir "${root}/run"

    log_info "Mounting pseudo-filesystems for chroot"

    mount -t proc /proc "${root}/proc"
    mount -t sysfs /sys "${root}/sys"
    mount --rbind /sys "${root}/sys"
    mount --rbind /dev "${root}/dev"
    mount --rbind /run "${root}/run"

    if is_uefi; then
        mount --make-rslave "${root}/sys"
        mount --make-rslave "${root}/dev"
    fi
}

# Unmount chroot pseudo-filesystems
unmount_chroot_fs() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    log_info "Unmounting chroot pseudo-filesystems"

    umount "${root}/proc" 2>/dev/null || true
    umount "${root}/sys" 2>/dev/null || true
    umount "${root}/dev" 2>/dev/null || true
    umount "${root}/run" 2>/dev/null || true
}

# Copy resolv.conf for network access inside chroot
copy_resolv_conf() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    # systemd-resolved: use upstream DNS directly (stub resolver 127.0.0.53 won't work in chroot)
    if [[ -L /etc/resolv.conf ]] && readlink /etc/resolv.conf | grep -q /run/systemd/resolve; then
        if [[ -f /run/systemd/resolve/resolv.conf ]]; then
            cp /run/systemd/resolve/resolv.conf "${root}/etc/resolv.conf"
            log_info "Copied upstream resolv.conf (systemd-resolved detected)"
            return
        fi
    fi

    # Standard resolv.conf: dereference symlinks
    if [[ -f /etc/resolv.conf ]]; then
        cp -L /etc/resolv.conf "${root}/etc/resolv.conf"
        log_info "Copied resolv.conf (dereferenced)"
        return
    fi

    # Fallback: write public DNS servers
    log_warn "No resolv.conf found on host, using fallback DNS"
    echo "nameserver 8.8.8.8" > "${root}/etc/resolv.conf"
    echo "nameserver 1.1.1.1" >> "${root}/etc/resolv.conf"
}

# Setup chroot environment for package installation
setup_chroot() {
    mount_chroot_fs
    copy_resolv_conf

    # Copy user.conf into chroot for reference
    if [[ -f "${SCRIPT_DIR}/config/user.conf" ]]; then
        cp "${SCRIPT_DIR}/config/user.conf" "${GENTOO_ROOT:-/mnt/gentoo}/root/user.conf"
    fi

    log_info "Chroot environment ready"
}

# Teardown chroot environment
teardown_chroot() {
    unmount_chroot_fs
    log_info "Chroot environment cleaned up"
}
