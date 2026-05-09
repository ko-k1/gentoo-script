#!/usr/bin/env bash
#
# platform/laptop.sh - Laptop-specific setup (power management, thermals)
#

# Apply laptop-specific optimizations
apply_laptop_optimizations() {
    log_info "Applying laptop optimizations"

    # CPU governor: schedutil for balance
    configure_cpu_governor "schedutil"

    # I/O scheduler optimization
    configure_io_scheduler

    # Sysctl tuning for laptop (power + responsiveness)
    apply_laptop_sysctl

    # Power management setup
    setup_power_management

    # Thermal management
    setup_thermal_management
}

# Configure CPU governor for laptop
configure_cpu_governor() {
    local governor="$1"
    log_info "Setting CPU governor: $governor"

    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    case "$INIT_SYSTEM" in
        openrc)
            ensure_dir "${root}/etc/conf.d"
            cat > "${root}/etc/conf.d/cpupower" << EOF
# CPU governor for laptop (balance performance/power)
governor="${governor}"
EOF
            ;;
        systemd)
            ensure_dir "${root}/etc/systemd/system"
            cat > "${root}/etc/systemd/system/cpupower.service" << EOF
[Unit]
Description=Set CPU governor to ${governor}

[Service]
Type=oneshot
ExecStart=/usr/bin/cpupower frequency-set -g ${governor}

[Install]
WantedBy=multi-user.target
EOF
            ;;
    esac
}

# Configure I/O scheduler for laptop
configure_io_scheduler() {
    log_info "Configuring I/O scheduler for laptop"

    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    # Use bfq for better power efficiency
    ensure_dir "${root}/etc/udev/rules.d"
    cat > "${root}/etc/udev/rules.d/60-scheduler.rules" << 'EOF'
# Set scheduler for NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"

# Set scheduler for SSD (bfq for power efficiency)
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="bfq"

# Set scheduler for rotating disks
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF
}

# Apply sysctl tuning for laptop
apply_laptop_sysctl() {
    log_info "Applying laptop sysctl tuning"

    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    ensure_dir "${root}/etc/sysctl.d"
    cat > "${root}/etc/sysctl.d/99-laptop.conf" << 'EOF'
# Laptop tuning - power efficiency + responsiveness

# Reduce latency for interactive use
kernel.sched_latency_ns=12000000
kernel.sched_min_granularity_ns=4000000
kernel.sched_wakeup_granularity_ns=2000000

# VM tuning - reduce disk writes for battery life
vm.dirty_ratio=15
vm.dirty_background_ratio=5
vm.swappiness=10
vm.vfs_cache_pressure=100
vm.laptop_mode=5

# Reduce disk writes
vm.dirty_expire_centisecs=6000
vm.dirty_writeback_centisecs=12000

# Network tuning
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216

# Disable NMI watchdog (saves power)
kernel.nmi_watchdog=0
EOF
}

# Setup TLP and power management
setup_power_management() {
    log_info "Setting up TLP power management"

    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    # Install TLP
    chroot_run "emerge --ask=n sys-power/tlp"

    # Configure TLP
    cat > "${root}/etc/tlp.conf" << 'EOF'
# TLP laptop power management config

# Operation mode: auto, bat, ac
TLP_DEFAULT_MODE="auto"

# CPU scaling
CPU_SCALING_GOVERNOR_ON_AC="performance"
CPU_SCALING_GOVERNOR_ON_BAT="powersave"

# CPU frequency limits
CPU_MIN_PERF_ON_AC=0
CPU_MAX_PERF_ON_AC=100
CPU_MIN_PERF_ON_BAT=0
CPU_MAX_PERF_ON_BAT=70

# Disk power management
DISK_APM_LEVEL_ON_AC="254 254"
DISK_APM_LEVEL_ON_BAT="128 128"

# PCIe power savings
PCIE_ASPM_ON_AC="default"
PCIE_ASPM_ON_BAT="powersupersave"

# USB autosuspend
USB_AUTOSUSPEND=1

# WiFi power savings
WIFI_PWR_ON_AC="off"
WIFI_PWR_ON_BAT="on"

# Runtime PM
RUNTIME_PM_ON_AC="on"
RUNTIME_PM_ON_BAT="auto"
EOF

    case "$INIT_SYSTEM" in
        openrc)
            chroot_run "rc-update add tlp default"
            ;;
        systemd)
            chroot_run "systemctl enable tlp"
            ;;
    esac

    # Install powertop for diagnostics
    chroot_run "emerge --ask=n sys-power/powertop"

    # Auto-tune powertop
    cat > "${root}/etc/systemd/system/powertop.service" << 'EOF'
[Unit]
Description=Powertop auto-tune

[Service]
Type=oneshot
ExecStart=/usr/sbin/powertop --auto-tune

[Install]
WantedBy=multi-user.target
EOF
}

# Setup thermal management
setup_thermal_management() {
    log_info "Setting up thermal management"

    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    # Install acpid for ACPI events
    chroot_run "emerge --ask=n sys-power/acpid"

    case "$INIT_SYSTEM" in
        openrc)
            chroot_run "rc-update add acpid default"
            ;;
        systemd)
            chroot_run "systemctl enable acpid"
            ;;
    esac

    # Install thermald (Intel thermal daemon)
    chroot_run "emerge --ask=n sys-power/thermald" 2>/dev/null || {
        log_warn "thermald not available for this platform"
    }

    case "$INIT_SYSTEM" in
        openrc)
            chroot_run "rc-update add thermald default" 2>/dev/null || true
            ;;
        systemd)
            chroot_run "systemctl enable thermald" 2>/dev/null || true
            ;;
    esac

    # Setup laptop-mode-tools for advanced power saving
    chroot_run "emerge --ask=n sys-power/laptop-mode-tools" 2>/dev/null || {
        log_warn "laptop-mode-tools not available"
    }

    log_info "Thermal management configured"
}
