#!/usr/bin/env bash
#
# lib/kernel.sh - Kernel installation (gentoo-sources or gentoo-kernel-bin)
#

# Install kernel based on config
install_kernel() {
    case "$KERNEL_TYPE" in
        gentoo-sources)
            install_gentoo_sources
            ;;
        gentoo-kernel-bin)
            install_gentoo_kernel_bin
            ;;
        *)
            die "Unknown kernel type: $KERNEL_TYPE"
            ;;
    esac
}

# Install gentoo-kernel-bin (pre-built)
install_gentoo_kernel_bin() {
    local pkg="sys-kernel/gentoo-kernel-bin"
    if [[ -n "$KERNEL_VERSION" ]]; then
        pkg="${pkg}:${KERNEL_VERSION}"
    fi

    log_info "Installing binary kernel: $pkg"
    chroot_run "emerge --ask=n ${pkg}" || die "Failed to install $pkg"

    # Ensure initramfs if needed
    chroot_run "eselect kernel list" || true

    log_info "Binary kernel installed"
}

# Install gentoo-sources and compile
install_gentoo_sources() {
    local pkg="sys-kernel/gentoo-sources"
    if [[ -n "$KERNEL_VERSION" ]]; then
        pkg="${pkg}:${KERNEL_VERSION}"
    fi

    log_info "Installing kernel sources: $pkg"
    chroot_run "emerge --ask=n ${pkg}" || die "Failed to install $pkg"

    # Install required tools
    chroot_run "emerge --ask=n sys-kernel/genkernel sys-kernel/linux-firmware"

    # Generate optimized kernel config
    generate_kernel_config

    # Compile kernel
    log_info "Compiling kernel..."
    chroot_run "genkernel --install --no-clean --menuconfig=no all" || {
        log_warn "genkernel failed, falling back to manual build"
        build_kernel_manual
    }

    log_info "Kernel compiled and installed"
}

# Generate optimized kernel config
generate_kernel_config() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    log_info "Generating optimized kernel config"

    # Start with default config
    chroot_run "cd /usr/src/linux && make defconfig"

    # Apply platform-specific optimizations
    case "$PLATFORM" in
        laptop)
            apply_laptop_kernel_config
            ;;
        desktop)
            apply_desktop_kernel_config
            ;;
        server)
            apply_server_kernel_config
            ;;
    esac

    # Apply arch-specific tweaks
    apply_arch_kernel_config

    log_info "Kernel config generated"
}

# Laptop-specific kernel config
apply_laptop_kernel_config() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    log_info "Applying laptop kernel config options"

    chroot_run "cd /usr/src/linux && scripts/config \
        --enable ACPI \
        --enable ACPI_CPU_FREQ_POWEST \
        --enable ACPI_THERMAL \
        --enable X86_INTEL_PSTATE \
        --enable CPU_FREQ_STAT \
        --enable CPU_FREQ_DEFAULT_GOV_SCHEDUTIL \
        --enable CPU_FREQ_GOV_POWERSAVE \
        --enable CPU_FREQ_GOV_PERFORMANCE \
        --enable CPU_FREQ_GOV_ONDEMAND \
        --enable SUSPEND \
        --enable HIBERNATION \
        --enable PM_DEBUG \
        --enable TOSHIBA_ACPI \
        --enable THINKPAD_ACPI \
        --enable AC \
        --enable BATTERY \
        --enable POWER_SUPPLY \
        --enable IWLWIFI \
        --enable CFG80211 \
        --enable MAC80211"
}

# Desktop-specific kernel config
apply_desktop_kernel_config() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    log_info "Applying desktop kernel config options"

    chroot_run "cd /usr/src/linux && scripts/config \
        --enable DRM \
        --enable DRM_KMS_HELPER \
        --enable DRM_I915 \
        --enable DRM_AMDGPU \
        --enable DRM_NOUVEAU \
        --enable FB_EFI \
        --enable EFI_STUB \
        --enable EFI_MIXED"
}

# Server-specific kernel config
apply_server_kernel_config() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    log_info "Applying server kernel config options"

    chroot_run "cd /usr/src/linux && scripts/config \
        --disable FB \
        --disable FB_EFI \
        --disable DRM \
        --disable SOUND \
        --enable EXT4_FS \
        --enable BTRFS_FS \
        --enable XFS_FS \
        --enable ZFS_FS"
}

# Architecture-specific kernel config tweaks
apply_arch_kernel_config() {
    case "$ARCH" in
        amd64)
            chroot_run "cd /usr/src/linux && scripts/config \
                --enable X86_64 \
                --enable X86_MCE \
                --enable MICROCODE \
                --enable MICROCODE_INTEL \
                --enable MICROCODE_AMD"
            ;;
        aarch64)
            chroot_run "cd /usr/src/linux && scripts/config \
                --enable ARM64 \
                --enable ARM_AMBA \
                --enable ARM_CPUIDLE"
            ;;
    esac
}

# Manual kernel build fallback
build_kernel_manual() {
    log_info "Building kernel manually..."
    chroot_run "cd /usr/src/linux && make -j$(nproc) bzImage modules"
    chroot_run "cd /usr/src/linux && make modules_install"
    chroot_run "cd /usr/src/linux && make install"
}

# Install kernel firmware
install_firmware() {
    log_info "Installing kernel firmware"
    chroot_run "emerge --ask=n sys-kernel/linux-firmware" || {
        log_warn "Failed to install linux-firmware"
    }
}
