#!/usr/bin/env bash
#
# lib/accelerate.sh - ccache, binhost, distcc setup
#

# Setup all acceleration features
setup_acceleration() {
    setup_ccache
    setup_binhost
    setup_distcc
}

# Setup ccache
setup_ccache() {
    if [[ "$ENABLE_CCACHE" != "yes" ]]; then
        log_info "ccache disabled"
        return
    fi

    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    log_info "Setting up ccache (size: $CCACHE_SIZE)"

    # Install ccache
    chroot_run "emerge --ask=n dev-util/ccache" || die "Failed to install ccache"

    # Configure ccache in make.conf
    chroot_run "echo 'FEATURES=\"\${FEATURES} ccache\"' >> /etc/portage/make.conf"
    chroot_run "echo \"CCACHE_DIR=\\\"/var/cache/ccache\\\"\" >> /etc/portage/make.conf"
    chroot_run "echo \"CCACHE_SIZE=\\\"${CCACHE_SIZE}\\\"\" >> /etc/portage/make.conf"

    # Create ccache directory
    ensure_dir "${root}/var/cache/ccache"
    chroot_run "ccache --max-size=${CCACHE_SIZE}"

    log_info "ccache configured"
}

# Setup binary package host
setup_binhost() {
    if [[ "$ENABLE_BINHOST" != "yes" ]]; then
        log_info "binhost disabled"
        return
    fi

    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    log_info "Setting up binary packages"

    # Enable FEATURES for binary packages
    chroot_run "echo 'FEATURES=\"\${FEATURES} buildpkg getbinpkg\"' >> /etc/portage/make.conf"

    # Configure binhost URL if provided
    if [[ -n "$BINHOST_URL" ]]; then
        chroot_run "echo \"PORTAGE_BINHOST=\\\"${BINHOST_URL}\\\"\" >> /etc/portage/make.conf"
        log_info "Binhost URL set: $BINHOST_URL"
    else
        log_info "Using local binary packages only"
        chroot_run "echo 'PKGDIR=\"/var/cache/binpkgs\"' >> /etc/portage/make.conf"
    fi

    # Create binpkgs directory
    ensure_dir "${root}/var/cache/binpkgs"

    log_info "Binary packages configured"
}

# Setup distcc
setup_distcc() {
    if [[ "$ENABLE_DISTCC" != "yes" ]]; then
        log_info "distcc disabled"
        return
    fi

    if [[ -z "$DISTCC_HOSTS" ]]; then
        log_warn "distcc enabled but no DISTCC_HOSTS specified"
        return
    fi

    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    log_info "Setting up distcc with hosts: $DISTCC_HOSTS"

    # Install distcc
    chroot_run "emerge --ask=n sys-devel/distcc" || die "Failed to install distcc"

    # Configure distcc
    chroot_run "echo \"DISTCC_HOSTS=\\\"${DISTCC_HOSTS}\\\"\" >> /etc/portage/make.conf"
    chroot_run "echo 'FEATURES=\"\${FEATURES} distcc\"' >> /etc/portage/make.conf"

    # Set MAKEOPTS for distcc
    local n_hosts
    n_hosts=$(echo "$DISTCC_HOSTS" | wc -w)
    local total_jobs=$(( n_hosts * 2 + 1 ))
    chroot_run "sed -i 's/^MAKEOPTS=.*/MAKEOPTS=\"-j${total_jobs}\"/' /etc/portage/make.conf"

    # Configure distcc allowed clients
    ensure_dir "${root}/etc/distcc"
    echo "192.168.0.0/16" > "${root}/etc/distcc/clients.allow"
    echo "127.0.0.1" >> "${root}/etc/distcc/clients.allow"

    case "$INIT_SYSTEM" in
        openrc)
            chroot_run "rc-update add distccd default"
            ;;
        systemd)
            chroot_run "systemctl enable distccd"
            ;;
    esac

    log_info "distcc configured with ${n_hosts} hosts, ${total_jobs} jobs"
}

# Create local binhost (for sharing builds)
create_local_binhost() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    local binhost_dir="${root}/var/cache/binpkgs"

    log_info "Local binhost directory: $binhost_dir"

    # Create Packages metadata
    chroot_run "cd /var/cache/binpkgs && emaint binhost --fix" || true

    log_info "Local binhost updated"
}

# Quick build packages for binhost
build_binhost_packages() {
    log_info "Building binary packages for @world..."
    chroot_run "emerge --ask=n --getbinpkg --usepkgonly --emptytree @world" || {
        log_warn "Not all packages have binaries available"
    }
}
