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
    if [[ -f /etc/resolv.conf ]]; then
        cp /etc/resolv.conf "${root}/etc/resolv.conf"
        log_info "Copied resolv.conf"
    fi
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
