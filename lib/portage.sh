#!/usr/bin/env bash
#
# lib/portage.sh - USE flags, profile selection, portage config
#

# Initialize portage directory structure
init_portage_dirs() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    ensure_dir "${root}/etc/portage/repos.conf"
    ensure_dir "${root}/etc/portage/package.use"
    ensure_dir "${root}/etc/portage/package.accept_keywords"
    ensure_dir "${root}/etc/portage/package.license"
    ensure_dir "${root}/etc/portage/env"

    log_info "Portage directories initialized"
}

# Configure Gentoo repository (initial sync always uses rsync for compatibility)
configure_gentoo_repo() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    local repo_file="${root}/etc/portage/repos.conf/gentoo.conf"

    cat > "$repo_file" << 'REPO'
[gentoo]
location = /var/db/repos/gentoo
sync-type = rsync
sync-uri = rsync://rsync.gentoo.org/gentoo-portage
auto-sync = yes
sync-rsync-verify-jobs = 1
sync-rsync-verify-metamanifest = yes
sync-rsync-verify-max-age = 24
REPO

    log_info "Gentoo repo configured (initial sync-type: rsync)"
}

# Switch to git sync after Portage is updated (supports git sync)
finalize_sync_config() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    local repo_file="${root}/etc/portage/repos.conf/gentoo.conf"

    if [[ "$SYNC_TYPE" != "git" ]]; then
        return
    fi

    log_info "Switching gentoo repo to git sync..."

    cat > "$repo_file" << 'REPO'
[gentoo]
location = /var/db/repos/gentoo
sync-type = git
sync-uri = https://github.com/gentoo-mirror/gentoo.git
auto-sync = yes
sync-git-verify-commit-signature = yes
REPO

    log_info "Gentoo repo switched to git sync"
}

# Apply USE flags
apply_use_flags() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    local use_file="${root}/etc/portage/package.use/custom"

    if [[ -n "$USE_ADD" ]] || [[ -n "$USE_REMOVE" ]]; then
        log_info "Applying custom USE flags"

        if [[ -n "$USE_ADD" ]]; then
            echo "# USE flags added by gentoo-script" > "$use_file"
            echo "*/* ${USE_ADD}" >> "$use_file"
        fi

        if [[ -n "$USE_REMOVE" ]]; then
            echo "# USE flags removed by gentoo-script" >> "$use_file"
            for flag in $USE_REMOVE; do
                echo "*/* -${flag}" >> "$use_file"
            done
        fi
    fi
}

# Apply accept keywords
apply_accept_keywords() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    local kw_file="${root}/etc/portage/package.accept_keywords/custom"

    if [[ -n "$ACCEPT_KEYWORDS_EXTRA" ]]; then
        log_info "Applying custom keywords"
        echo "# Custom keywords" > "$kw_file"
        echo "$ACCEPT_KEYWORDS_EXTRA" >> "$kw_file"
    fi
}

# Apply license accepts
apply_license_accepts() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    local lic_file="${root}/etc/portage/package.license/custom"

    if [[ -n "$LICENSE_ACCEPT" ]]; then
        log_info "Applying custom license accepts"
        echo "# Custom license accepts" > "$lic_file"
        echo "*/* ${LICENSE_ACCEPT}" >> "$lic_file"
    fi
}

# Sync portage tree
sync_portage() {
    log_info "Syncing Portage tree..."

    if chroot_run "emerge --sync"; then
        log_info "Portage tree synced"
        return
    fi

    log_warn "emerge --sync failed, trying webrsync..."
    if chroot_run "command -v emerge-webrsync"; then
        chroot_run "emerge-webrsync" || log_warn "emerge-webrsync also failed"
    else
        log_warn "emerge-webrsync not available in stage3"
    fi

    log_info "Portage tree sync attempted"
    verify_portage_tree
}

# Verify portage tree is usable
verify_portage_tree() {
    log_info "Verifying portage tree..."
    chroot_run "[[ -d /var/db/repos/gentoo/profiles ]]" || {
        die "Portage tree missing or empty after sync"
    }
    log_info "Portage tree verified"
}

# Update @world with automatic circular dependency resolution
update_world() {
    local opts="--update --deep --newuse --verbose --backtrack=30"

    if [[ "$ENABLE_BINHOST" == "yes" ]] && [[ -n "$BINHOST_URL" ]]; then
        opts="${opts} --getbinpkg"
    fi

    log_info "Updating @world..."

    # Attempt 1: --backtrack=30 handles most cases
    _emerge_world "emerge ${opts} @world" && return

    local log_file="$EMERGE_LOG"

    # Non-circular failure — show output and abort
    if ! grep -qi "circular" "$log_file"; then
        _emerge_fail "$log_file" "Non-circular dependency error"
    fi

    # Attempt 2: higher backtrack resolves ~95% of circular deps
    local opts_high="${opts/--backtrack=30/--backtrack=200}"
    log_warn "Circular dependency detected, retrying with --backtrack=200..."
    _emerge_world "emerge ${opts_high} @world" && return

    # Attempt 3: parse and apply Portage's suggested USE fix
    log_warn "Trying Portage's suggested circular dependency resolution..."
    if _resolve_circular_dep "$log_file"; then
        _emerge_world "emerge ${opts} @world" && return
    fi

    _emerge_fail "$log_file" "Circular dependency could not be resolved automatically"
}

# Internal: run emerge, capture output, return success
_emerge_world() {
    local cmd="$1"
    EMERGE_LOG=$(mktemp) || die "Failed to create temp file"
    if chroot_run "$cmd" 2>&1 | tee "$EMERGE_LOG"; then
        rm -f "$EMERGE_LOG"
        unset EMERGE_LOG
        log_info "@world update complete"
        return 0
    fi
    return 1
}

# Internal: print failure output and die
_emerge_fail() {
    local log_file="$1"
    local reason="$2"
    log_error "emerge --update @world failed: $reason. Last 30 lines:"
    tail -30 "$log_file" >&2
    rm -f "$log_file"
    unset EMERGE_LOG
    die "Failed to update @world"
}

# Internal: parse emerge output, apply Portage's suggested USE changes, emerge --oneshot
_resolve_circular_dep() {
    local log_file="$1"
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    local break_file="${root}/etc/portage/package.use/circular-break"
    local in_suggestion=0
    local -a packages=()

    # Parse: "break this cycle by adjusting USE flags" then "cat/pkg: +/-flag ..."
    while IFS= read -r line; do
        local clean="$line"
        clean="${clean#* }"    # strip leading "* " prefix
        clean="${clean# }"

        if [[ "$in_suggestion" == "0" ]] && echo "$clean" | grep -qi "break this cycle"; then
            in_suggestion=1
            continue
        fi

        if [[ "$in_suggestion" == "1" ]]; then
            [[ -z "$clean" ]] && break
            if [[ "$clean" =~ ^[a-zA-Z0-9._+-]+/[a-zA-Z0-9._+-]+: ]]; then
                local atom="${clean%%: *}"
                local flags="${clean#*: }"
                packages+=("$atom")
                for flag in $flags; do
                    case "$flag" in
                        -*) echo "$atom $flag" ;;
                        +*) echo "$atom ${flag#+}" ;;
                    esac >> "$break_file"
                done
            fi
        fi
    done < "$log_file"

    if [[ "$in_suggestion" == "0" ]] || [[ ${#packages[@]} -eq 0 ]]; then
        rm -f "$break_file"
        return 1
    fi

    # Deduplicate and emerge --oneshot to break the cycle
    local unique_pkgs
    unique_pkgs=$(printf "%s\n" "${packages[@]}" | sort -u | tr '\n' ' ')
    log_info "Breaking circular dep: emerging $unique_pkgs"

    chroot_run "emerge --ask=n --oneshot $unique_pkgs" || {
        rm -f "$break_file"
        return 1
    }

    rm -f "$break_file"
    return 0
}

# Install base packages
install_base_packages() {
    local packages="sys-kernel/linux-firmware sys-fs/e2fsprogs sys-fs/btrfs-progs sys-fs/xfsprogs net-misc/dhcpcd"

    case "$INIT_SYSTEM" in
        openrc)
            packages="${packages} sys-apps/openrc net-misc/netifrc"
            ;;
        systemd)
            packages="${packages} sys-apps/systemd"
            ;;
    esac

    log_info "Installing base packages: $packages"
    chroot_run "emerge --ask=n ${packages}" || die "Failed to install base packages"
}

# Apply platform-specific portage tweaks
apply_platform_tweaks() {
    case "$PLATFORM" in
        laptop)
            apply_laptop_tweaks
            ;;
        desktop)
            apply_desktop_tweaks
            ;;
        server)
            apply_server_tweaks
            ;;
    esac
}

# Laptop-specific portage config
apply_laptop_tweaks() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    log_info "Applying laptop-specific portage tweaks"

    # Add power management packages
    cat > "${root}/etc/portage/package.use/laptop" << 'EOF'
# Laptop power management
sys-power/tlp usb
sys-power/cpupower nls
EOF
}

# Desktop-specific portage config
apply_desktop_tweaks() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    log_info "Applying desktop-specific portage tweaks"
}

# Server-specific portage config
apply_server_tweaks() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"

    log_info "Applying server-specific portage tweaks"

    cat > "${root}/etc/portage/make.conf.server" << 'EOF'
# Server optimizations - minimal bloat
USE="${USE} -cups -bluetooth -pulseaudio -pipewire"
EOF
}
