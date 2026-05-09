#!/usr/bin/env bash
#
# install.sh - Gentoo Automated Install Script with Optimization
#
# Usage: ./install.sh [--config path/to/user.conf] [--profile desktop|laptop|server]
#

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
GENTOO_ROOT="${GENTOO_ROOT:-/mnt/gentoo}"
WORK_DIR="${WORK_DIR:-/tmp/gentoo-install}"
DRY_RUN="${DRY_RUN:-0}"
DEBUG="${DEBUG:-0}"

# ============================================================
# Load libraries
# ============================================================
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/arch.sh"
source "${SCRIPT_DIR}/lib/stage3.sh"
source "${SCRIPT_DIR}/lib/partition.sh"
source "${SCRIPT_DIR}/lib/chroot.sh"
source "${SCRIPT_DIR}/lib/makeconf.sh"
source "${SCRIPT_DIR}/lib/portage.sh"
source "${SCRIPT_DIR}/lib/kernel.sh"
source "${SCRIPT_DIR}/lib/system.sh"
source "${SCRIPT_DIR}/lib/accelerate.sh"
source "${SCRIPT_DIR}/lib/desktop.sh"

# ============================================================
# Parse arguments
# ============================================================
parse_args() {
    local user_conf=""
    local profile=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                user_conf="$2"
                shift 2
                ;;
            --profile)
                profile="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --debug)
                DEBUG=1
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                die "Unknown argument: $1"
                ;;
        esac
    done

    # Load configuration in order: defaults -> profile -> user
    load_config "$user_conf" "$profile"
}

# Show help
show_help() {
    cat << 'HELP'
Gentoo Automated Install Script

Usage: ./install.sh [OPTIONS]

Options:
  --config PATH       Path to user configuration file
  --profile PROFILE   Profile to use (desktop, laptop, server)
  --dry-run           Show what would be done without executing
  --debug             Enable debug output
  --help, -h          Show this help

Examples:
  ./install.sh --profile laptop --config config/user.conf
  ./install.sh --profile desktop
  ./install.sh --config /path/to/my.conf

Required in user.conf:
  TARGET_DISK="sda"  # or nvme0n1
HELP
}

# Load configuration
load_config() {
    local user_conf="$1"
    local profile="$2"

    # 1. Load defaults
    log_info "Loading defaults..."
    source "${SCRIPT_DIR}/config/defaults.conf"

    # 2. Load profile if specified
    if [[ -n "$profile" ]]; then
        log_info "Loading profile: $profile"
        local profile_file="${SCRIPT_DIR}/config/profiles/${profile}.conf"
        if [[ -f "$profile_file" ]]; then
            source "$profile_file"
        else
            die "Profile not found: $profile_file"
        fi
    fi

    # 3. Load user config
    if [[ -n "$user_conf" ]]; then
        log_info "Loading user config: $user_conf"
        if [[ -f "$user_conf" ]]; then
            source "$user_conf"
        else
            die "User config not found: $user_conf"
        fi
    fi

    # Validate required settings
    validate_config
}

# Validate configuration
validate_config() {
    log_info "Validating configuration..."

    # Required
    [[ -n "$TARGET_DISK" ]] || die "TARGET_DISK is required"
    validate_in "$ARCH" "amd64" "aarch64"
    validate_in "$PLATFORM" "desktop" "laptop" "server"
    validate_in "$INIT_SYSTEM" "openrc" "systemd"
    validate_in "$ROOT_FS" "ext4" "btrfs" "xfs" "zfs"
    validate_in "$KERNEL_TYPE" "gentoo-sources" "gentoo-kernel-bin"
    validate_in "$BOOTLOADER" "grub" "systemd-boot" "none"
    validate_in "$SYNC_TYPE" "git" "rsync"

    if [[ "$INSTALL_DESKTOP" == "yes" ]]; then
        validate_in "$DESKTOP_ENV" "gnome" "kde" "xfce" "hyprland" "sway" "none"
    fi

    if [[ "$DESKTOP_ENV" == "hyprland" ]]; then
        validate_in "$HYPRLAND_DM" "greetd" "sddm" "none"
        validate_in "$HYPRLAND_USE_OVERLAY" "yes" "no"
    fi

    log_info "Configuration valid"
}

# ============================================================
# Installation phases
# ============================================================

# Phase 1: Pre-flight checks
phase_preflight() {
    log_step "=== Phase 1: Pre-flight ==="

    if [[ "$DRY_RUN" != "1" ]]; then
        require_root
        require_cmd blkid
    fi
    require_cmd curl
    require_cmd tar

    ensure_dir "$WORK_DIR"

    # Load arch config
    load_arch_config "$ARCH"

    # Detect CPU flags
    detect_cpu_flags "$ARCH"

    log_info "Pre-flight complete"
}

# Phase 2: Partition and format
phase_partition() {
    log_step "=== Phase 2: Partition and Format ==="

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would partition /dev/${TARGET_DISK} with ${ROOT_FS}"
        return
    fi

    partition_disk "$TARGET_DISK"
    create_filesystems "$TARGET_DISK" "$ROOT_FS"
    mount_partitions "$TARGET_DISK" "$ROOT_FS"

    log_info "Partition and format complete"
}

# Phase 3: Stage3
phase_stage3() {
    log_step "=== Phase 3: Stage3 ==="

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would download/extract stage3"
        return
    fi

    prepare_stage3
    download_checksums
    extract_stage3

    log_info "Stage3 complete"
}

# Phase 4: Chroot setup
phase_chroot_setup() {
    log_step "=== Phase 4: Chroot Setup ==="

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would setup chroot"
        return
    fi

    setup_chroot

    log_info "Chroot setup complete"
}

# Phase 5: Optimization and Portage
phase_optimize() {
    log_step "=== Phase 5: Optimization and Portage ==="

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would configure make.conf and Portage"
        return
    fi

    init_portage_dirs
    configure_gentoo_repo
    generate_make_conf "$ARCH"
    apply_use_flags
    apply_accept_keywords
    apply_license_accepts
    apply_platform_tweaks

    log_info "Optimization complete"
}

# Phase 6: Sync and update world
phase_sync_update() {
    log_step "=== Phase 6: Sync and Update @world ==="

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would sync Portage and update @world"
        return
    fi

    sync_portage
    update_world

    log_info "Sync and update complete"
}

# Phase 7: Kernel
phase_kernel() {
    log_step "=== Phase 7: Kernel ==="

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would install kernel ($KERNEL_TYPE)"
        return
    fi

    install_kernel
    install_firmware

    log_info "Kernel complete"
}

# Phase 8: System configuration
phase_system() {
    log_step "=== Phase 8: System Configuration ==="

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would configure system"
        return
    fi

    configure_system "$TARGET_DISK"

    log_info "System configuration complete"
}

# Phase 9: Acceleration
phase_acceleration() {
    log_step "=== Phase 9: Acceleration ==="

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would setup acceleration (ccache/binhost/distcc)"
        return
    fi

    setup_acceleration

    log_info "Acceleration setup complete"
}

# Phase 10: Desktop
phase_desktop() {
    log_step "=== Phase 10: Desktop ==="

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would install desktop ($DESKTOP_ENV)"
        return
    fi

    setup_desktop

    log_info "Desktop setup complete"
}

# Phase 11: Platform optimizations
phase_platform() {
    log_step "=== Phase 11: Platform Optimizations ==="

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would apply platform optimizations ($PLATFORM)"
        return
    fi

    # Source platform script
    source "${SCRIPT_DIR}/platform/${PLATFORM}.sh"

    # Apply optimizations
    case "$PLATFORM" in
        desktop)
            apply_desktop_optimizations
            ;;
        laptop)
            apply_laptop_optimizations
            ;;
        server)
            apply_server_optimizations 2>/dev/null || log_info "No server optimizations to apply"
            ;;
    esac

    log_info "Platform optimizations complete"
}

# Phase 12: Finalize
phase_finalize() {
    log_step "=== Phase 12: Finalize ==="

    if [[ "$DRY_RUN" == "1" ]]; then
        log_info "[DRY-RUN] Would finalize installation"
        return
    fi

    # Cleanup
    rm -f "${GENTOO_ROOT}/root/user.conf" 2>/dev/null || true

    # Unmount chroot
    teardown_chroot
    unmount_partitions

    log_info "=========================================="
    log_info "Gentoo installation complete!"
    log_info "=========================================="
    log_info "Target disk: /dev/${TARGET_DISK}"
    log_info "Architecture: ${ARCH}"
    log_info "Platform: ${PLATFORM}"
    log_info "Init system: ${INIT_SYSTEM}"
    log_info "Filesystem: ${ROOT_FS}"
    log_info "Kernel: ${KERNEL_TYPE}"
    if [[ "$INSTALL_DESKTOP" == "yes" ]]; then
        log_info "Desktop: ${DESKTOP_ENV}"
    fi
    log_info "=========================================="
    log_info "Reboot to start your new Gentoo system!"
    log_info "=========================================="
}

# ============================================================
# Main
# ============================================================
main() {
    parse_args "$@"

    log_info "Gentoo Automated Install"
    log_info "Arch: ${ARCH} | Platform: ${PLATFORM} | Init: ${INIT_SYSTEM}"
    log_info "Disk: ${TARGET_DISK} | FS: ${ROOT_FS} | Kernel: ${KERNEL_TYPE}"

    phase_preflight
    phase_partition
    phase_stage3
    phase_chroot_setup
    phase_optimize
    phase_sync_update
    phase_kernel
    phase_system
    phase_acceleration
    phase_desktop
    phase_platform
    phase_finalize

    log_info "Done!"
}

# Run main
main "$@"
