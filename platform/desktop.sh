#!/usr/bin/env bash
#
# platform/desktop.sh - Desktop-specific setup
#

# Apply desktop-specific optimizations
apply_desktop_optimizations() {
    log_info "Applying desktop optimizations"

    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    # CPU governor: performance for desktop
    configure_cpu_governor "performance"

    # I/O scheduler optimization
    configure_io_scheduler

    # Sysctl tuning for desktop
    apply_desktop_sysctl
}

# Configure CPU governor
configure_cpu_governor() {
    local governor="$1"
    log_info "Setting CPU governor: $governor"

    # This will be applied via init scripts after boot
    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    case "$INIT_SYSTEM" in
        openrc)
            ensure_dir "${root}/etc/conf.d"
            cat > "${root}/etc/conf.d/cpupower" << EOF
# CPU governor for desktop
governor="${governor}"
EOF
            ;;
        systemd)
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

# Configure I/O scheduler
configure_io_scheduler() {
    log_info "Configuring I/O scheduler for desktop"

    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    # Use mq-deadline or bfq for desktop responsiveness
    ensure_dir "${root}/etc/udev/rules.d"
    cat > "${root}/etc/udev/rules.d/60-scheduler.rules" << 'EOF'
# Set scheduler for NVMe
ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"

# Set scheduler for SSD
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

# Set scheduler for rotating disks
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF
}

# Apply sysctl tuning for desktop
apply_desktop_sysctl() {
    log_info "Applying desktop sysctl tuning"

    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    ensure_dir "${root}/etc/sysctl.d"
    cat > "${root}/etc/sysctl.d/99-desktop.conf" << 'EOF'
# Desktop responsiveness tuning

# Reduce latency
kernel.sched_latency_ns=12000000
kernel.sched_min_granularity_ns=4000000
kernel.sched_wakeup_granularity_ns=2000000

# VM tuning for interactive desktop
vm.dirty_ratio=20
vm.dirty_background_ratio=10
vm.swappiness=10
vm.vfs_cache_pressure=50

# Network tuning
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 65536 16777216
EOF
}
