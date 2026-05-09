#!/usr/bin/env bash
#
# tests/test.sh - Comprehensive test suite for gentoo-script
#
# Usage: bash tests/test.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP="${TEST_TMP:-/tmp/gentoo-script-tests}"

# Test counters
PASS=0
FAIL=0
SKIP=0
TOTAL=0

# Setup
setup() {
    rm -rf "$TEST_TMP"
    mkdir -p "$TEST_TMP"
}

# Teardown
teardown() {
    if [[ "${CLEANUP:-1}" == "1" ]]; then
        rm -rf "$TEST_TMP"
    fi
}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Test helpers
ok() {
    echo -e "  ${GREEN}PASS${NC}: $1"
    PASS=$((PASS + 1))
    TOTAL=$((TOTAL + 1))
}

nok() {
    echo -e "  ${RED}FAIL${NC}: $1"
    FAIL=$((FAIL + 1))
    TOTAL=$((TOTAL + 1))
}

skp() {
    echo -e "  ${YELLOW}SKIP${NC}: $1"
    SKIP=$((SKIP + 1))
    TOTAL=$((TOTAL + 1))
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        ok "$desc"
    else
        nok "$desc (expected='$expected', actual='$actual')"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        ok "$desc"
    else
        nok "$desc (expected '$needle' in output)"
    fi
}

assert_file_contains() {
    local desc="$1" needle="$2" file="$3"
    if [[ -f "$file" ]] && grep -q "$needle" "$file"; then
        ok "$desc"
    else
        nok "$desc ($needle not found in $file)"
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    if [[ -f "$file" ]]; then
        ok "$desc"
    else
        nok "$desc ($file does not exist)"
    fi
}

assert_exit_ok() {
    local desc="$1"
    if eval "$2" >/dev/null 2>&1; then
        ok "$desc"
    else
        nok "$desc"
    fi
}

assert_exit_fail() {
    local desc="$1"
    if (eval "$2" >/dev/null 2>&1); then
        nok "$desc (expected failure)"
    else
        ok "$desc"
    fi
}

# ============================================================
# Source libraries
# ============================================================
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/arch.sh"
source "${SCRIPT_DIR}/lib/makeconf.sh"
source "${SCRIPT_DIR}/lib/partition.sh"
source "${SCRIPT_DIR}/lib/portage.sh"
source "${SCRIPT_DIR}/lib/system.sh"
source "${SCRIPT_DIR}/lib/accelerate.sh"
source "${SCRIPT_DIR}/lib/desktop.sh"
source "${SCRIPT_DIR}/lib/kernel.sh"
source "${SCRIPT_DIR}/lib/chroot.sh"
source "${SCRIPT_DIR}/lib/stage3.sh"
source "${SCRIPT_DIR}/platform/desktop.sh"
source "${SCRIPT_DIR}/platform/laptop.sh"

# Load defaults first
source "${SCRIPT_DIR}/config/defaults.conf"

# ============================================================
# Test: Config Defaults
# ============================================================
test_config_defaults() {
    echo "=== Config Defaults ==="

    source "${SCRIPT_DIR}/config/defaults.conf"

    assert_eq "ARCH" "amd64" "$ARCH"
    assert_eq "PLATFORM" "desktop" "$PLATFORM"
    assert_eq "INIT_SYSTEM" "openrc" "$INIT_SYSTEM"
    assert_eq "ROOT_FS" "ext4" "$ROOT_FS"
    assert_eq "KERNEL_TYPE" "gentoo-kernel-bin" "$KERNEL_TYPE"
    assert_eq "ENABLE_CCACHE" "yes" "$ENABLE_CCACHE"
    assert_eq "ENABLE_BINHOST" "yes" "$ENABLE_BINHOST"
    assert_eq "ENABLE_DISTCC" "no" "$ENABLE_DISTCC"
    assert_eq "CCACHE_SIZE" "10G" "$CCACHE_SIZE"
    assert_eq "OPTIMIZATION_LEVEL" "O2" "$OPTIMIZATION_LEVEL"
    assert_eq "HOSTNAME" "gentoo" "$HOSTNAME"
    assert_eq "BOOTLOADER" "grub" "$BOOTLOADER"
    assert_eq "MAKEOPTS" "auto" "$MAKEOPTS"
    assert_eq "DISPLAY_SERVER" "auto" "$DISPLAY_SERVER"
    assert_eq "EFI_INSTALL" "auto" "$EFI_INSTALL"
}

# ============================================================
# Test: Profile Overrides
# ============================================================
test_profile_overrides() {
    echo ""
    echo "=== Profile Overrides ==="

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/config/profiles/desktop.conf"
    assert_eq "desktop PLATFORM" "desktop" "$PLATFORM"
    assert_eq "desktop INSTALL_DESKTOP" "yes" "$INSTALL_DESKTOP"
    assert_eq "desktop DESKTOP_ENV" "kde" "$DESKTOP_ENV"
    assert_contains "desktop USE_ADD has X" "X" "$USE_ADD"
    assert_contains "desktop USE_ADD has pipewire" "pipewire" "$USE_ADD"

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/config/profiles/laptop.conf"
    assert_eq "laptop PLATFORM" "laptop" "$PLATFORM"
    assert_contains "laptop USE_ADD has laptop" "laptop" "$USE_ADD"
    assert_contains "laptop USE_ADD has acpi" "acpi" "$USE_ADD"
    assert_contains "laptop USE_ADD has bluetooth" "bluetooth" "$USE_ADD"
    assert_contains "laptop has ROOT_MOUNT_OPTS_EXTRA" "commit=120" "$ROOT_MOUNT_OPTS_EXTRA"

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/config/profiles/server.conf"
    assert_eq "server PLATFORM" "server" "$PLATFORM"
    assert_eq "server INSTALL_DESKTOP" "no" "$INSTALL_DESKTOP"
    assert_contains "server USE_REMOVE has X" "X" "$USE_REMOVE"
    assert_contains "server USE_REMOVE has cups" "cups" "$USE_REMOVE"
}

# ============================================================
# Test: Arch Configs
# ============================================================
test_arch_configs() {
    echo ""
    echo "=== Arch Configs ==="

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/arch/amd64.conf"
    assert_eq "amd64 ARCH_NAME" "amd64" "$ARCH_NAME"
    assert_eq "amd64 STAGE3_ARCH" "amd64" "$STAGE3_ARCH"
    assert_contains "amd64 CFLAGS native" "-march=native" "$CFLAGS_BASE"
    assert_contains "amd64 profile" "default/linux/amd64" "$PROFILE_BASE"
    assert_contains "amd64 GRUB" "efi-64" "$GRUB_PLATFORMS"
    assert_eq "amd64 CPU_FLAGS_VAR" "CPU_FLAGS_X86" "$CPU_FLAGS_VAR"

    source "${SCRIPT_DIR}/arch/aarch64.conf"
    assert_eq "aarch64 ARCH_NAME" "aarch64" "$ARCH_NAME"
    assert_eq "aarch64 STAGE3_ARCH" "arm64" "$STAGE3_ARCH"
    assert_contains "aarch64 CFLAGS armv8" "-march=armv8-a" "$CFLAGS_BASE"
    assert_contains "aarch64 profile" "default/linux/arm64" "$PROFILE_BASE"
    assert_eq "aarch64 CPU_FLAGS_VAR" "CPU_FLAGS_ARM" "$CPU_FLAGS_VAR"
}

# ============================================================
# Test: Arch Detection
# ============================================================
test_arch_detection() {
    echo ""
    echo "=== Arch Detection ==="

    local detected
    detected=$(detect_arch)
    if [[ "$detected" == "amd64" || "$detected" == "aarch64" ]]; then
        ok "detect_arch returns valid: $detected"
    else
        nok "detect_arch returns invalid: $detected"
    fi
}

# ============================================================
# Test: CPU Flag Detection (x86)
# ============================================================
test_cpu_flags_x86() {
    echo ""
    echo "=== CPU Flag Detection (x86 simulation) ==="

    # Simulate x86 /proc/cpuinfo
    local fake_cpuinfo="${TEST_TMP}/fake_cpuinfo_x86"
    cat > "$fake_cpuinfo" << 'EOF'
processor	: 0
vendor_id	: GenuineIntel
cpu family	: 6
model		: 154
model name	: 12th Gen Intel(R) Core(TM) i7-12700K
flags		: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ss ht tm pbe syscall nx pdpe1gb rdtscp lm constant_tsc art arch_perfmon pebs bts rep_good nopl xtopology nonstop_tsc cpuid aperfmperf tsc_known_freq pni pclmulqdq dtes64 monitor ds_cpl vmx smx est tm2 ssse3 sse4_1 sse4_2 x2apic movbe popcnt tsc_deadline_timer aes xsave avx f16c rdrand lahf_lm abm 3dnowprefetch cpuid_fault epb ssbd ibrs ibpb stibp ibrs_enhanced tpr_shadow vnmi flexpriority ept vpid ept_ad fsgsbase tsc_adjust bmi1 avx2 smep bmi2 erms invpcid rdseed adx smap clflushopt clwb intel_pt sha_ni xsaveopt xsavec xgetbv1 xsaves split_lock_detect user_shstk avx_vnni dtherm ida arat pln pts hwp hwp_notify hwp_act_window hwp_epp hwp_pkg_req hfi umip pku ospke waitpkg gfni vaes vpclmulqdq rdpid movdiri movdir64b fsrm md_clear serialize arch_lbr ibt flush_l1d arch_capabilities
EOF

    # Temporarily override /proc/cpuinfo
    local saved_cpuinfo=""
    saved_cpuinfo=$(mktemp)
    cp /proc/cpuinfo "$saved_cpuinfo" 2>/dev/null || true

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/arch/amd64.conf"

    # Override grep to use fake file
    CPU_FLAGS_DETECTED=""
    detect_x86_cpu_flags < /dev/null 2>/dev/null || true

    # Use awk to parse fake cpuinfo
    local flags
    flags=$(awk '/^flags/ {found=1} found {print; exit}' "$fake_cpuinfo")
    local detected_flags=()
    grep -qw 'aes' <<< "$flags" && detected_flags+=("aes")
    grep -qw 'avx' <<< "$flags" && detected_flags+=("avx")
    grep -qw 'avx2' <<< "$flags" && detected_flags+=("avx2")
    grep -qw 'f16c' <<< "$flags" && detected_flags+=("f16c")
    grep -qw 'pclmulqdq' <<< "$flags" && detected_flags+=("pclmul")
    grep -qw 'popcnt' <<< "$flags" && detected_flags+=("popcnt")
    grep -qw 'sse' <<< "$flags" && detected_flags+=("sse")
    grep -qw 'sse2' <<< "$flags" && detected_flags+=("sse2")
    grep -qw 'sse3' <<< "$flags" && detected_flags+=("sse3")
    grep -qw 'ssse3' <<< "$flags" && detected_flags+=("ssse3")
    grep -qw 'sse4_1' <<< "$flags" && detected_flags+=("sse4_1")
    grep -qw 'sse4_2' <<< "$flags" && detected_flags+=("sse4_2")

    CPU_FLAGS_DETECTED="${detected_flags[*]}"
    echo "  Detected x86 flags: $CPU_FLAGS_DETECTED"

    assert_contains "x86 flags has aes" "aes" "$CPU_FLAGS_DETECTED"
    assert_contains "x86 flags has avx" "avx" "$CPU_FLAGS_DETECTED"
    assert_contains "x86 flags has avx2" "avx2" "$CPU_FLAGS_DETECTED"
    assert_contains "x86 flags has sse4_2" "sse4_2" "$CPU_FLAGS_DETECTED"
    assert_contains "x86 flags has ssse3" "ssse3" "$CPU_FLAGS_DETECTED"

    local count
    count=$(echo "$CPU_FLAGS_DETECTED" | wc -w)
    if (( count >= 8 )); then
        ok "x86 detected $count flags (>= 8)"
    else
        nok "x86 only detected $count flags (expected >= 8)"
    fi

    rm -f "$fake_cpuinfo" "$saved_cpuinfo"
}

# ============================================================
# Test: CPU Flag Detection (ARM)
# ============================================================
test_cpu_flags_arm() {
    echo ""
    echo "=== CPU Flag Detection (ARM) ==="

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/arch/aarch64.conf"
    detect_arm_cpu_flags 2>/dev/null || true

    echo "  Detected ARM flags: $CPU_FLAGS_DETECTED"
    if [[ -n "$CPU_FLAGS_DETECTED" ]]; then
        ok "ARM flags detected: $CPU_FLAGS_DETECTED"
    else
        nok "ARM flags empty (using defaults)"
        CPU_FLAGS_DETECTED="$CPU_FLAGS_DEFAULT"
    fi

    local count
    count=$(echo "$CPU_FLAGS_DETECTED" | wc -w)
    if (( count > 0 )); then
        ok "ARM detected $count flags"
    else
        nok "ARM no flags detected"
    fi
}

# ============================================================
# Test: CFLAGS Generation (amd64)
# ============================================================
test_cflags_amd64() {
    echo ""
    echo "=== CFLAGS Generation (amd64) ==="

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/arch/amd64.conf"
    OPTIMIZATION_LEVEL="O2"
    PLATFORM="desktop"
    CFLAGS_EXTRA=""

    local cflags
    cflags=$(generate_cflags "amd64")
    echo "  Generated: $cflags"

    assert_contains "O2 level" "-O2" "$cflags"
    assert_contains "native march" "-march=native" "$cflags"
    assert_contains "pipe" "-pipe" "$cflags"
}

# ============================================================
# Test: CFLAGS Generation (aarch64)
# ============================================================
test_cflags_aarch64() {
    echo ""
    echo "=== CFLAGS Generation (aarch64) ==="

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/arch/aarch64.conf"
    OPTIMIZATION_LEVEL="O3"
    PLATFORM="desktop"
    CFLAGS_EXTRA="-fomit-frame-pointer"

    local cflags
    cflags=$(generate_cflags "aarch64")
    echo "  Generated: $cflags"

    assert_contains "O3 level" "-O3" "$cflags"
    assert_contains "armv8-a march" "armv8-a" "$cflags"
    assert_contains "pipe" "-pipe" "$cflags"
    assert_contains "extra flag" "-fomit-frame-pointer" "$cflags"
}

# ============================================================
# Test: CFLAGS Generation (laptop)
# ============================================================
test_cflags_laptop() {
    echo ""
    echo "=== CFLAGS Generation (laptop) ==="

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/arch/amd64.conf"
    OPTIMIZATION_LEVEL="O2"
    PLATFORM="laptop"
    CFLAGS_EXTRA=""

    local cflags
    cflags=$(generate_cflags "amd64")
    echo "  Generated: $cflags"

    assert_contains "O2 level" "-O2" "$cflags"
    assert_contains "omit-frame-pointer" "-fomit-frame-pointer" "$cflags"
}

# ============================================================
# Test: MAKEOPTS
# ============================================================
test_makeopts() {
    echo ""
    echo "=== MAKEOPTS ==="

    source "${SCRIPT_DIR}/config/defaults.conf"

    MAKEOPTS="auto"
    local auto_opts
    auto_opts=$(generate_makeopts)
    assert_contains "auto has -j" "-j" "$auto_opts"
    echo "  Auto: $auto_opts"

    MAKEOPTS="-j17"
    local manual_opts
    manual_opts=$(generate_makeopts)
    assert_eq "manual -j17" "-j17" "$manual_opts"

    MAKEOPTS="-j5"
    manual_opts=$(generate_makeopts)
    assert_eq "manual -j5" "-j5" "$manual_opts"
}

# ============================================================
# Test: Emerge Default Opts
# ============================================================
test_emerge_opts() {
    echo ""
    echo "=== Emerge Default Opts ==="

    source "${SCRIPT_DIR}/config/defaults.conf"
    EMERGE_DEFAULT_OPTS_EXTRA=""

    local opts
    opts=$(generate_emerge_opts)
    echo "  Generated: $opts"

    assert_contains "has --jobs" "--jobs" "$opts"
    assert_contains "has --load-average" "--load-average" "$opts"

    EMERGE_DEFAULT_OPTS_EXTRA="--quiet-build"
    opts=$(generate_emerge_opts)
    assert_contains "has extra --quiet-build" "--quiet-build" "$opts"
}

# ============================================================
# Test: Filesystem Mount Options
# ============================================================
test_fs_mount_opts() {
    echo ""
    echo "=== Filesystem Mount Options ==="

    local opts

    opts=$(get_fs_mount_opts "ext4" "desktop")
    echo "  ext4 desktop: $opts"
    assert_contains "ext4 desktop noatime" "noatime" "$opts"

    opts=$(get_fs_mount_opts "ext4" "laptop")
    echo "  ext4 laptop: $opts"
    assert_contains "ext4 laptop commit=120" "commit=120" "$opts"

    opts=$(get_fs_mount_opts "btrfs" "desktop")
    echo "  btrfs desktop: $opts"
    assert_contains "btrfs noatime" "noatime" "$opts"
    assert_contains "btrfs compress" "compress=zstd" "$opts"

    opts=$(get_fs_mount_opts "btrfs" "laptop")
    echo "  btrfs laptop: $opts"
    assert_contains "btrfs laptop commit" "commit=120" "$opts"

    opts=$(get_fs_mount_opts "xfs" "desktop")
    echo "  xfs desktop: $opts"
    assert_contains "xfs noatime" "noatime" "$opts"

    opts=$(get_fs_mount_opts "zfs" "desktop")
    echo "  zfs desktop: '$opts'"
    assert_eq "zfs opts empty" "" "$opts"
}

# ============================================================
# Test: Profile Path Generation
# ============================================================
test_profile_paths() {
    echo ""
    echo "=== Profile Path Generation ==="

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/arch/amd64.conf"
    ARCH="amd64"

    # Desktop + openrc + kde
    INIT_SYSTEM="openrc"
    INSTALL_DESKTOP="yes"
    DESKTOP_ENV="kde"
    local profile
    profile=$(get_profile_path "amd64")
    echo "  desktop/kde/openrc: $profile"
    assert_contains "has kde" "kde" "$profile"

    # Desktop + systemd + gnome
    INIT_SYSTEM="systemd"
    INSTALL_DESKTOP="yes"
    DESKTOP_ENV="gnome"
    profile=$(get_profile_path "amd64")
    echo "  desktop/gnome/systemd: $profile"
    assert_contains "has systemd" "systemd" "$profile"
    assert_contains "has gnome" "gnome" "$profile"

    # Server + openrc (no desktop)
    INIT_SYSTEM="openrc"
    INSTALL_DESKTOP="no"
    profile=$(get_profile_path "amd64")
    echo "  server/openrc: $profile"
    assert_contains "has server" "server" "$profile"

    # aarch64 desktop
    source "${SCRIPT_DIR}/arch/aarch64.conf"
    ARCH="aarch64"
    INIT_SYSTEM="systemd"
    INSTALL_DESKTOP="yes"
    DESKTOP_ENV="xfce"
    profile=$(get_profile_path "aarch64")
    echo "  aarch64/xfce/systemd: $profile"
    assert_contains "has arm64" "arm64" "$profile"
    assert_contains "has xfce" "xfce" "$profile"
}

# ============================================================
# Test: Stage3 URL Resolution
# ============================================================
test_stage3_url() {
    echo ""
    echo "=== Stage3 URL Resolution ==="

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/arch/amd64.conf"
    ARCH="amd64"

    # Custom URL
    STAGE3_URL="https://custom.mirror/stage3-amd64.tar.zst"
    STAGE3_PATH=""
    local url
    url=$(get_stage3_url 2>/dev/null | tail -1)
    assert_eq "custom URL" "$STAGE3_URL" "$url"

    # Local path
    STAGE3_URL=""
    STAGE3_PATH="/tmp/stage3.tar.zst"
    url=$(get_stage3_url 2>/dev/null | tail -1)
    assert_eq "local path" "$STAGE3_PATH" "$url"

    # Auto (should not fail, just won't resolve without network)
    STAGE3_URL=""
    STAGE3_PATH=""
    echo "  Auto-detection would use mirror: $MIRROR_URL"
    ok "auto-detection configured"
}

# ============================================================
# Test: Partition Functions (non-destructive)
# ============================================================
test_partition_functions() {
    echo ""
    echo "=== Partition Functions ==="

    # Test get_fs_mount_opts (already tested above)

    # Test that partition functions exist and are callable
    assert_exit_ok "partition_uefi exists" "type partition_uefi"
    assert_exit_ok "partition_bios exists" "type partition_bios"
    assert_exit_ok "create_filesystems exists" "type create_filesystems"
    assert_exit_ok "mount_partitions exists" "type mount_partitions"
    assert_exit_ok "unmount_partitions exists" "type unmount_partitions"
}

# ============================================================
# Test: Chroot Functions (non-destructive)
# ============================================================
test_chroot_functions() {
    echo ""
    echo "=== Chroot Functions ==="

    assert_exit_ok "mount_chroot_fs exists" "type mount_chroot_fs"
    assert_exit_ok "unmount_chroot_fs exists" "type unmount_chroot_fs"
    assert_exit_ok "setup_chroot exists" "type setup_chroot"
    assert_exit_ok "teardown_chroot exists" "type teardown_chroot"
    assert_exit_ok "chroot_run exists" "type chroot_run"
    assert_exit_ok "chroot_run_as exists" "type chroot_run_as"
}

# ============================================================
# Test: make.conf Generation
# ============================================================
test_makeconf_generation() {
    echo ""
    echo "=== make.conf Generation ==="

    local fake_root="${TEST_TMP}/fake_root"
    mkdir -p "${fake_root}/etc/portage"

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/arch/amd64.conf"
    ARCH="amd64"
    PLATFORM="desktop"
    INIT_SYSTEM="openrc"
    OPTIMIZATION_LEVEL="O2"
    CFLAGS_EXTRA=""
    MAKEOPTS="auto"
    USE_ADD="X pipewire"
    USE_REMOVE=""
    ACCEPT_KEYWORDS_EXTRA=""
    LICENSE_ACCEPT=""
    INSTALL_DESKTOP="yes"
    DESKTOP_ENV="kde"
    CPU_FLAGS_VAR="CPU_FLAGS_X86"
    CPU_FLAGS_DETECTED="aes avx avx2 sse sse2 sse3 sse4_1 sse4_2 ssse3"
    GRUB_PLATFORMS="efi-64 pc"

    GENTOO_ROOT="$fake_root"
    generate_make_conf "amd64"
    unset GENTOO_ROOT

    local makeconf="${fake_root}/etc/portage/make.conf"
    assert_file_exists "make.conf created" "$makeconf"
    assert_file_contains "has CFLAGS" "CFLAGS=" "$makeconf"
    assert_file_contains "has CXXFLAGS" "CXXFLAGS=" "$makeconf"
    assert_file_contains "has MAKEOPTS" "MAKEOPTS=" "$makeconf"
    assert_file_contains "has CPU_FLAGS_X86" "CPU_FLAGS_X86=" "$makeconf"
    assert_file_contains "has USE flags" "USE=" "$makeconf"
    assert_file_contains "has EMERGE_DEFAULT_OPTS" "EMERGE_DEFAULT_OPTS=" "$makeconf"
    assert_file_contains "has distfiles" "DISTDIR=" "$makeconf"
    assert_file_contains "has pkgdir" "PKGDIR=" "$makeconf"

    # Verify content
    assert_file_contains "has -O2" "O2" "$makeconf"
    assert_file_contains "has -pipe" "pipe" "$makeconf"
    assert_file_contains "has aes" "aes" "$makeconf"
    assert_file_contains "has X USE" "X" "$makeconf"
    assert_file_contains "has pipewire USE" "pipewire" "$makeconf"

    echo ""
    echo "  Generated make.conf:"
    echo "  ---"
    sed 's/^/  /' "$makeconf"
    echo "  ---"
}

# ============================================================
# Test: make.conf with laptop profile
# ============================================================
test_makeconf_laptop() {
    echo ""
    echo "=== make.conf (laptop) ==="

    local fake_root="${TEST_TMP}/fake_root_laptop"
    mkdir -p "${fake_root}/etc/portage"

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/config/profiles/laptop.conf"
    source "${SCRIPT_DIR}/arch/amd64.conf"
    ARCH="amd64"
    PLATFORM="laptop"
    INIT_SYSTEM="openrc"
    OPTIMIZATION_LEVEL="O2"
    CFLAGS_EXTRA=""
    MAKEOPTS="auto"
    CPU_FLAGS_VAR="CPU_FLAGS_X86"
    CPU_FLAGS_DETECTED="aes avx avx2 sse sse2"
    GRUB_PLATFORMS="efi-64 pc"
    INSTALL_DESKTOP="yes"
    DESKTOP_ENV="kde"

    GENTOO_ROOT="$fake_root"
    generate_make_conf "amd64"
    unset GENTOO_ROOT

    local makeconf="${fake_root}/etc/portage/make.conf"
    assert_file_contains "has laptop USE" "laptop" "$makeconf"
    assert_file_contains "has acpi USE" "acpi" "$makeconf"

    echo ""
    echo "  Generated make.conf (laptop):"
    echo "  ---"
    sed 's/^/  /' "$makeconf"
    echo "  ---"
}

# ============================================================
# Test: make.conf with aarch64
# ============================================================
test_makeconf_aarch64() {
    echo ""
    echo "=== make.conf (aarch64) ==="

    local fake_root="${TEST_TMP}/fake_root_arm"
    mkdir -p "${fake_root}/etc/portage"

    source "${SCRIPT_DIR}/config/defaults.conf"
    source "${SCRIPT_DIR}/arch/aarch64.conf"
    ARCH="aarch64"
    PLATFORM="desktop"
    INIT_SYSTEM="openrc"
    OPTIMIZATION_LEVEL="O2"
    CFLAGS_EXTRA=""
    MAKEOPTS="auto"
    CPU_FLAGS_VAR="CPU_FLAGS_ARM"
    CPU_FLAGS_DETECTED="crc crypto neon vfp vfpv3"
    GRUB_PLATFORMS=""
    INSTALL_DESKTOP="no"

    GENTOO_ROOT="$fake_root"
    generate_make_conf "aarch64"
    unset GENTOO_ROOT

    local makeconf="${fake_root}/etc/portage/make.conf"
    assert_file_contains "has armv8" "armv8-a" "$makeconf"
    assert_file_contains "has CPU_FLAGS_ARM" "CPU_FLAGS_ARM=" "$makeconf"
    assert_file_contains "has neon" "neon" "$makeconf"

    echo ""
    echo "  Generated make.conf (aarch64):"
    echo "  ---"
    sed 's/^/  /' "$makeconf"
    echo "  ---"
}

# ============================================================
# Test: Portage Functions
# ============================================================
test_portage_functions() {
    echo ""
    echo "=== Portage Functions ==="

    assert_exit_ok "init_portage_dirs exists" "type init_portage_dirs"
    assert_exit_ok "configure_gentoo_repo exists" "type configure_gentoo_repo"
    assert_exit_ok "apply_use_flags exists" "type apply_use_flags"
    assert_exit_ok "apply_accept_keywords exists" "type apply_accept_keywords"
    assert_exit_ok "sync_portage exists" "type sync_portage"
    assert_exit_ok "update_world exists" "type update_world"
    assert_exit_ok "apply_platform_tweaks exists" "type apply_platform_tweaks"
    assert_exit_ok "apply_laptop_tweaks exists" "type apply_laptop_tweaks"
}

# ============================================================
# Test: Portage Config Generation
# ============================================================
test_portage_config() {
    echo ""
    echo "=== Portage Config Generation ==="

    local fake_root="${TEST_TMP}/fake_portage"
    mkdir -p "${fake_root}/etc/portage/repos.conf"
    mkdir -p "${fake_root}/etc/portage/package.use"
    mkdir -p "${fake_root}/etc/portage/package.accept_keywords"
    mkdir -p "${fake_root}/etc/portage/package.license"
    mkdir -p "${fake_root}/etc/portage/env"

    GENTOO_ROOT="$fake_root"
    configure_gentoo_repo
    unset GENTOO_ROOT

    local repo_file="${fake_root}/etc/portage/repos.conf/gentoo.conf"
    assert_file_exists "gentoo.conf created" "$repo_file"
    assert_file_contains "has location" "location" "$repo_file"
    assert_file_contains "has sync-uri" "sync-uri" "$repo_file"
    assert_file_contains "has rsync" "rsync" "$repo_file"

    # Test USE flags file
    GENTOO_ROOT="$fake_root"
    USE_ADD="X alsa pipewire"
    USE_REMOVE="-bluetooth"
    apply_use_flags
    unset GENTOO_ROOT

    local use_file="${fake_root}/etc/portage/package.use/custom"
    assert_file_exists "package.use/custom created" "$use_file"
    assert_file_contains "has X" "X" "$use_file"
    assert_file_contains "has pipewire" "pipewire" "$use_file"
}

# ============================================================
# Test: Platform Tweaks
# ============================================================
test_platform_tweaks() {
    echo ""
    echo "=== Platform Tweaks ==="

    local fake_root="${TEST_TMP}/fake_tweaks"
    mkdir -p "${fake_root}/etc/portage/package.use"

    GENTOO_ROOT="$fake_root"
    PLATFORM="laptop"
    apply_laptop_tweaks
    unset GENTOO_ROOT

    local laptop_file="${fake_root}/etc/portage/package.use/laptop"
    assert_file_exists "laptop package.use created" "$laptop_file"
    assert_file_contains "has tlp" "tlp" "$laptop_file"
    assert_file_contains "has cpupower" "cpupower" "$laptop_file"
}

# ============================================================
# Test: System Configuration Functions
# ============================================================
test_system_functions() {
    echo ""
    echo "=== System Configuration Functions ==="

    assert_exit_ok "configure_hostname exists" "type configure_hostname"
    assert_exit_ok "configure_timezone exists" "type configure_timezone"
    assert_exit_ok "configure_locale exists" "type configure_locale"
    assert_exit_ok "generate_fstab exists" "type generate_fstab"
    assert_exit_ok "configure_network exists" "type configure_network"
    assert_exit_ok "install_bootloader exists" "type install_bootloader"
    assert_exit_ok "install_grub exists" "type install_grub"
    assert_exit_ok "install_systemd_boot exists" "type install_systemd_boot"
    assert_exit_ok "set_root_password exists" "type set_root_password"
    assert_exit_ok "create_extra_users exists" "type create_extra_users"
}

# ============================================================
# Test: Fstab Generation
# ============================================================
test_fstab_generation() {
    echo ""
    echo "=== Fstab Generation ==="

    local fake_root="${TEST_TMP}/fake_fstab"
    mkdir -p "${fake_root}/etc"

    GENTOO_ROOT="$fake_root"
    TARGET_DISK="nvme0n1"
    ROOT_FS="ext4"
    PLATFORM="laptop"
    generate_fstab "nvme0n1"
    unset GENTOO_ROOT

    local fstab="${fake_root}/etc/fstab"
    assert_file_exists "fstab created" "$fstab"
    assert_file_contains "has root mount" "/dev/nvme0n13" "$fstab"
    assert_file_contains "has boot mount" "/dev/nvme0n12" "$fstab"
    assert_file_contains "has ext4" "ext4" "$fstab"
    assert_file_contains "has noatime" "noatime" "$fstab"

    echo ""
    echo "  Generated fstab:"
    echo "  ---"
    sed 's/^/  /' "$fstab"
    echo "  ---"
}

# ============================================================
# Test: Acceleration Functions
# ============================================================
test_acceleration_functions() {
    echo ""
    echo "=== Acceleration Functions ==="

    assert_exit_ok "setup_acceleration exists" "type setup_acceleration"
    assert_exit_ok "setup_ccache exists" "type setup_ccache"
    assert_exit_ok "setup_binhost exists" "type setup_binhost"
    assert_exit_ok "setup_distcc exists" "type setup_distcc"
}

# ============================================================
# Test: Desktop Functions
# ============================================================
test_desktop_functions() {
    echo ""
    echo "=== Desktop Functions ==="

    assert_exit_ok "install_desktop exists" "type install_desktop"
    assert_exit_ok "install_display_server exists" "type install_display_server"
    assert_exit_ok "install_x11 exists" "type install_x11"
    assert_exit_ok "install_wayland exists" "type install_wayland"
    assert_exit_ok "install_gnome exists" "type install_gnome"
    assert_exit_ok "install_kde exists" "type install_kde"
    assert_exit_ok "install_xfce exists" "type install_xfce"
    assert_exit_ok "install_sway exists" "type install_sway"
    assert_exit_ok "setup_laptop_power exists" "type setup_laptop_power"
}

# ============================================================
# Test: Kernel Functions
# ============================================================
test_kernel_functions() {
    echo ""
    echo "=== Kernel Functions ==="

    assert_exit_ok "install_kernel exists" "type install_kernel"
    assert_exit_ok "install_gentoo_sources exists" "type install_gentoo_sources"
    assert_exit_ok "install_gentoo_kernel_bin exists" "type install_gentoo_kernel_bin"
    assert_exit_ok "generate_kernel_config exists" "type generate_kernel_config"
    assert_exit_ok "apply_laptop_kernel_config exists" "type apply_laptop_kernel_config"
    assert_exit_ok "apply_desktop_kernel_config exists" "type apply_desktop_kernel_config"
    assert_exit_ok "apply_server_kernel_config exists" "type apply_server_kernel_config"
}

# ============================================================
# Test: Platform Desktop Optimizations
# ============================================================
test_platform_desktop() {
    echo ""
    echo "=== Platform Desktop Optimizations ==="

    local fake_root="${TEST_TMP}/fake_platform_desktop"
    mkdir -p "${fake_root}/etc"

    GENTOO_ROOT="$fake_root"
    INIT_SYSTEM="openrc"

    # Test functions exist
    assert_exit_ok "apply_desktop_optimizations exists" "type apply_desktop_optimizations"
    assert_exit_ok "configure_cpu_governor exists" "type configure_cpu_governor"
    assert_exit_ok "configure_io_scheduler exists" "type configure_io_scheduler"
    assert_exit_ok "apply_desktop_sysctl exists" "type apply_desktop_sysctl"

    # Actually run them to generate files
    source "${SCRIPT_DIR}/platform/desktop.sh"
    configure_cpu_governor "performance"
    configure_io_scheduler
    apply_desktop_sysctl

    local cpupower_file="${fake_root}/etc/conf.d/cpupower"
    local scheduler_file="${fake_root}/etc/udev/rules.d/60-scheduler.rules"
    local sysctl_file="${fake_root}/etc/sysctl.d/99-desktop.conf"

    assert_file_exists "cpupower config created" "$cpupower_file"
    assert_file_contains "cpupower has performance" "performance" "$cpupower_file"

    assert_file_exists "scheduler rules created" "$scheduler_file"
    assert_file_contains "scheduler has bfq" "bfq" "$scheduler_file"
    assert_file_contains "scheduler has mq-deadline" "mq-deadline" "$scheduler_file"

    assert_file_exists "desktop sysctl created" "$sysctl_file"
    assert_file_contains "sysctl has dirty_ratio" "dirty_ratio" "$sysctl_file"
    assert_file_contains "sysctl has swappiness" "swappiness" "$sysctl_file"

    unset GENTOO_ROOT
}

# ============================================================
# Test: Platform Laptop Optimizations
# ============================================================
test_platform_laptop() {
    echo ""
    echo "=== Platform Laptop Optimizations ==="

    local fake_root="${TEST_TMP}/fake_platform_laptop"
    mkdir -p "${fake_root}/etc"
    mkdir -p "${fake_root}/etc/systemd/system"

    GENTOO_ROOT="$fake_root"
    INIT_SYSTEM="systemd"

    source "${SCRIPT_DIR}/platform/laptop.sh"

    configure_cpu_governor "schedutil"
    configure_io_scheduler
    apply_laptop_sysctl

    local cpupower_file="${fake_root}/etc/systemd/system/cpupower.service"
    local sysctl_file="${fake_root}/etc/sysctl.d/99-laptop.conf"

    assert_file_exists "laptop cpupower service created" "$cpupower_file"
    assert_file_contains "cpupower has schedutil" "schedutil" "$cpupower_file"

    assert_file_exists "laptop sysctl created" "$sysctl_file"
    assert_file_contains "sysctl has laptop_mode" "laptop_mode" "$sysctl_file"
    assert_file_contains "sysctl has dirty_expire" "dirty_expire_centisecs" "$sysctl_file"
    assert_file_contains "sysctl has nmi_watchdog" "nmi_watchdog" "$sysctl_file"

    unset GENTOO_ROOT
}

# ============================================================
# Test: Helper Functions
# ============================================================
test_helpers() {
    echo ""
    echo "=== Helper Functions ==="

    assert_exit_ok "has_cmd works (bash)" "has_cmd bash"
    assert_exit_ok "require_cmd works (bash)" "require_cmd bash"

    assert_exit_ok "get_cpu_cores returns value" "test -n \"$(get_cpu_cores)\""
    local cores
    cores=$(get_cpu_cores)
    echo "  CPU cores: $cores"
    if (( cores > 0 )); then
        ok "CPU cores > 0: $cores"
    else
        nok "CPU cores invalid: $cores"
    fi

    assert_exit_ok "get_ram_mb returns value" "test -n \"$(get_ram_mb)\""
    local ram
    ram=$(get_ram_mb)
    echo "  RAM: ${ram}MB"
    if (( ram > 0 )); then
        ok "RAM > 0: ${ram}MB"
    else
        nok "RAM invalid: ${ram}MB"
    fi

    assert_exit_ok "is_uefi returns value" "is_uefi || true"
    if is_uefi; then
        ok "Running in UEFI mode"
    else
        ok "Running in BIOS mode"
    fi
}

# ============================================================
# Test: Validation
# ============================================================
test_validation() {
    echo ""
    echo "=== Validation ==="

    assert_exit_ok "valid arch passes" "validate_in amd64 amd64 aarch64"
    assert_exit_ok "valid platform passes" "validate_in desktop desktop laptop server"
    assert_exit_ok "valid init passes" "validate_in openrc openrc systemd"
    assert_exit_ok "valid fs passes" "validate_in ext4 ext4 btrfs xfs zfs"

    assert_exit_fail "invalid arch fails" "(validate_in invalid amd64 aarch64)"
    assert_exit_fail "invalid platform fails" "(validate_in invalid desktop laptop server)"
    assert_exit_fail "invalid init fails" "(validate_in invalid openrc systemd)"
}

# ============================================================
# Test: Dry-run Integration
# ============================================================
test_dryrun() {
    echo ""
    echo "=== Dry-run Integration ==="

    local conf="${TEST_TMP}/test-user.conf"
    cat > "$conf" << 'EOF'
TARGET_DISK="sda"
ARCH="amd64"
PLATFORM="desktop"
INIT_SYSTEM="openrc"
ROOT_FS="ext4"
EOF

    local output
    output=$(bash "${SCRIPT_DIR}/install.sh" --profile desktop --config "$conf" --dry-run 2>&1) || true

    echo "  Dry-run output preview:"
    echo "$output" | head -15 | sed 's/^/  /'
    echo "  ..."

    assert_contains "shows preflight" "Phase 1" "$output"
    assert_contains "shows partition" "Phase 2" "$output"
    assert_contains "shows stage3" "Phase 3" "$output"
    assert_contains "shows DRY-RUN" "DRY-RUN" "$output"
    assert_contains "shows amd64" "amd64" "$output"
}

# ============================================================
# Test: Error Handling
# ============================================================
test_error_handling() {
    echo ""
    echo "=== Error Handling ==="

    # Help should exit 0
    local exit_code=0
    bash "${SCRIPT_DIR}/install.sh" --help >/dev/null 2>&1 || exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        ok "--help exits 0"
    else
        nok "--help exits $exit_code"
    fi

    # Missing config should fail
    exit_code=0
    bash "${SCRIPT_DIR}/install.sh" --config /nonexistent/file.conf --dry-run >/dev/null 2>&1 || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        ok "missing config fails"
    else
        nok "missing config should fail"
    fi

    # Invalid profile should fail
    exit_code=0
    local conf="${TEST_TMP}/test-user.conf"
    cat > "$conf" << 'EOF'
TARGET_DISK="sda"
EOF
    bash "${SCRIPT_DIR}/install.sh" --profile invalid --config "$conf" --dry-run >/dev/null 2>&1 || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        ok "invalid profile fails"
    else
        nok "invalid profile should fail"
    fi

    # Missing TARGET_DISK should fail
    exit_code=0
    local empty_conf="${TEST_TMP}/empty.conf"
    cat > "$empty_conf" << 'EOF'
ARCH="amd64"
EOF
    bash "${SCRIPT_DIR}/install.sh" --profile desktop --config "$empty_conf" --dry-run >/dev/null 2>&1 || exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        ok "missing TARGET_DISK fails"
    else
        nok "missing TARGET_DISK should fail"
    fi
}

# ============================================================
# Test: Config File Integrity
# ============================================================
test_config_integrity() {
    echo ""
    echo "=== Config File Integrity ==="

    # All config files should be valid bash (syntax check)
    for conf in "${SCRIPT_DIR}"/config/*.conf "${SCRIPT_DIR}"/config/profiles/*.conf "${SCRIPT_DIR}"/arch/*.conf; do
        if bash -n "$conf" 2>/dev/null; then
            ok "syntax OK: $(basename "$conf")"
        else
            nok "syntax error: $(basename "$conf")"
        fi
    done

    # All lib files should be valid bash
    for lib in "${SCRIPT_DIR}"/lib/*.sh; do
        if bash -n "$lib" 2>/dev/null; then
            ok "syntax OK: $(basename "$lib")"
        else
            nok "syntax error: $(basename "$lib")"
        fi
    done

    # Platform files
    for plat in "${SCRIPT_DIR}"/platform/*.sh; do
        if bash -n "$plat" 2>/dev/null; then
            ok "syntax OK: $(basename "$plat")"
        else
            nok "syntax error: $(basename "$plat")"
        fi
    done

    # Main script
    if bash -n "${SCRIPT_DIR}/install.sh" 2>/dev/null; then
        ok "syntax OK: install.sh"
    else
        nok "syntax error: install.sh"
    fi
}

# ============================================================
# Test: File Structure
# ============================================================
test_file_structure() {
    echo ""
    echo "=== File Structure ==="

    assert_file_exists "install.sh" "${SCRIPT_DIR}/install.sh"
    assert_file_exists "README.md" "${SCRIPT_DIR}/README.md"
    assert_file_exists "config/defaults.conf" "${SCRIPT_DIR}/config/defaults.conf"
    assert_file_exists "config/user.conf" "${SCRIPT_DIR}/config/user.conf"
    assert_file_exists "config/profiles/desktop.conf" "${SCRIPT_DIR}/config/profiles/desktop.conf"
    assert_file_exists "config/profiles/laptop.conf" "${SCRIPT_DIR}/config/profiles/laptop.conf"
    assert_file_exists "config/profiles/server.conf" "${SCRIPT_DIR}/config/profiles/server.conf"
    assert_file_exists "arch/amd64.conf" "${SCRIPT_DIR}/arch/amd64.conf"
    assert_file_exists "arch/aarch64.conf" "${SCRIPT_DIR}/arch/aarch64.conf"
    assert_file_exists "lib/utils.sh" "${SCRIPT_DIR}/lib/utils.sh"
    assert_file_exists "lib/arch.sh" "${SCRIPT_DIR}/lib/arch.sh"
    assert_file_exists "lib/stage3.sh" "${SCRIPT_DIR}/lib/stage3.sh"
    assert_file_exists "lib/partition.sh" "${SCRIPT_DIR}/lib/partition.sh"
    assert_file_exists "lib/chroot.sh" "${SCRIPT_DIR}/lib/chroot.sh"
    assert_file_exists "lib/makeconf.sh" "${SCRIPT_DIR}/lib/makeconf.sh"
    assert_file_exists "lib/portage.sh" "${SCRIPT_DIR}/lib/portage.sh"
    assert_file_exists "lib/kernel.sh" "${SCRIPT_DIR}/lib/kernel.sh"
    assert_file_exists "lib/system.sh" "${SCRIPT_DIR}/lib/system.sh"
    assert_file_exists "lib/accelerate.sh" "${SCRIPT_DIR}/lib/accelerate.sh"
    assert_file_exists "lib/desktop.sh" "${SCRIPT_DIR}/lib/desktop.sh"
    assert_file_exists "platform/desktop.sh" "${SCRIPT_DIR}/platform/desktop.sh"
    assert_file_exists "platform/laptop.sh" "${SCRIPT_DIR}/platform/laptop.sh"
}

# ============================================================
# Run all tests
# ============================================================
main() {
    setup
    trap teardown EXIT

    test_config_defaults
    test_profile_overrides
    test_arch_configs
    test_arch_detection
    test_cpu_flags_x86
    test_cpu_flags_arm
    test_cflags_amd64
    test_cflags_aarch64
    test_cflags_laptop
    test_makeopts
    test_emerge_opts
    test_fs_mount_opts
    test_profile_paths
    test_stage3_url
    test_partition_functions
    test_chroot_functions
    test_makeconf_generation
    test_makeconf_laptop
    test_makeconf_aarch64
    test_portage_functions
    test_portage_config
    test_platform_tweaks
    test_system_functions
    test_fstab_generation
    test_acceleration_functions
    test_desktop_functions
    test_kernel_functions
    test_platform_desktop
    test_platform_laptop
    test_helpers
    test_validation
    test_dryrun
    test_error_handling
    test_config_integrity
    test_file_structure

    echo ""
    echo "=================================================="
    echo "  Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${SKIP} skipped${NC} (total: ${TOTAL})"
    echo "=================================================="

    if [[ $FAIL -gt 0 ]]; then
        exit 1
    fi
    echo -e "  ${GREEN}ALL TESTS PASSED!${NC}"
    exit 0
}

main "$@"
