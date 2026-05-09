#!/usr/bin/env bash
#
# lib/utils.sh - Shared helpers for Gentoo automated install
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*" >&2
    fi
}

# Exit on error with message
die() {
    log_error "$*"
    exit 1
}

# Require root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root"
    fi
}

# Run command inside chroot
chroot_run() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    log_debug "chroot_run: $*"
    chroot "$root" /bin/bash -c "$*"
}

# Run command inside chroot as non-root user
chroot_run_as() {
    local user="$1"
    shift
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    log_debug "chroot_run_as ($user): $*"
    chroot "$root" /bin/su - "$user" -c "$*"
}

# Prompt with yes/no defaulting to yes
prompt_yes() {
    local msg="$1"
    local default="${2:-y}"
    local choice
    if [[ "$default" == "y" ]]; then
        echo -ne "${GREEN}${msg} [Y/n]: ${NC}"
    else
        echo -ne "${GREEN}${msg} [y/N]: ${NC}"
    fi
    read -r choice
    choice="${choice:-$default}"
    [[ "$choice" =~ ^[Yy]$ ]]
}

# Prompt for a value with default
prompt_value() {
    local msg="$1"
    local default="$2"
    local value
    echo -ne "${CYAN}${msg}${NC} [${default}]: "
    read -r value
    echo "${value:-$default}"
}

# Prompt from a list of options
prompt_select() {
    local msg="$1"
    shift
    local options=("$@")
    local i
    echo -e "${CYAN}${msg}${NC}"
    for i in "${!options[@]}"; do
        echo -e "  ${GREEN}$((i+1))${NC}) ${options[$i]}"
    done
    local choice
    while true; do
        echo -ne "Select (1-${#options[@]}): "
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "${options[$((choice-1))]}"
            return
        fi
        log_error "Invalid selection"
    done
}

# Check if a command exists
has_cmd() {
    command -v "$1" &>/dev/null
}

# Require a command
require_cmd() {
    if ! has_cmd "$1"; then
        die "Required command not found: $1"
    fi
}

# Retry a command with backoff
retry() {
    local max="${1:-3}"
    local delay="${2:-5}"
    shift 2
    local attempt=1
    while (( attempt <= max )); do
        log_info "Attempt $attempt/$max: $*"
        if "$@"; then
            return 0
        fi
        log_warn "Attempt $attempt failed, retrying in ${delay}s..."
        sleep "$delay"
        (( attempt++ ))
    done
    die "Command failed after $max attempts: $*"
}

# Validate a value is in a list
validate_in() {
    local value="$1"
    shift
    for item in "$@"; do
        [[ "$value" == "$item" ]] && return 0
    done
    die "Invalid value '$value'. Must be one of: $*"
}

# Get number of CPU cores
get_cpu_cores() {
    local cores
    if has_cmd nproc; then
        cores=$(nproc)
    elif [[ -f /proc/cpuinfo ]]; then
        cores=$(grep -c '^processor' /proc/cpuinfo)
    else
        cores=1
    fi
    echo "$cores"
}

# Get total RAM in MB
get_ram_mb() {
    if [[ -f /proc/meminfo ]]; then
        local kb
        kb=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
        echo $(( kb / 1024 ))
    else
        echo 2048
    fi
}

# Detect disk size in GB
get_disk_size_gb() {
    local disk="$1"
    local sectors
    sectors=$(blockdev --getsz "/dev/$disk" 2>/dev/null || echo 0)
    echo $(( sectors * 512 / 1024 / 1024 / 1024 ))
}

# Check if running in UEFI mode
is_uefi() {
    [[ -d /sys/firmware/efi ]]
}

# Check if systemd is available on host
host_has_systemd() {
    [[ -d /run/systemd/system ]]
}

# Create directory if not exists
ensure_dir() {
    mkdir -p "$@"
}

# Backup a file
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        cp "$file" "${file}.bak.$(date +%s)"
        log_info "Backed up $file"
    fi
}
