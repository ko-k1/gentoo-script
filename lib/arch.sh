#!/usr/bin/env bash
#
# lib/arch.sh - Architecture detection + stage3 URL resolution
#

# Detect host architecture
detect_arch() {
    local host_arch
    host_arch=$(uname -m)
    case "$host_arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            die "Unsupported architecture: $host_arch"
            ;;
    esac
}

# Load architecture-specific config
load_arch_config() {
    local arch="$1"
    local arch_file="${SCRIPT_DIR}/arch/${arch}.conf"
    if [[ -f "$arch_file" ]]; then
        log_info "Loading architecture config: $arch_file"
        source "$arch_file"
    else
        die "No architecture config found for: $arch"
    fi
}

# Detect CPU flags for current architecture
detect_cpu_flags() {
    local arch="$1"
    case "$arch" in
        amd64)
            detect_x86_cpu_flags
            ;;
        aarch64)
            detect_arm_cpu_flags
            ;;
    esac
}

# Detect x86 CPU flags
detect_x86_cpu_flags() {
    if [[ -f /proc/cpuinfo ]]; then
        local flags
        flags=$(grep -m1 '^flags' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -s ' ' || true)
        local detected=()

        grep -qw 'aes' <<< "$flags" && detected+=("aes") || true
        grep -qw 'avx' <<< "$flags" && detected+=("avx") || true
        grep -qw 'avx2' <<< "$flags" && detected+=("avx2") || true
        grep -qw 'f16c' <<< "$flags" && detected+=("f16c") || true
        grep -qw 'fma' <<< "$flags" && detected+=("fma3") || true
        grep -qw 'mmx' <<< "$flags" && detected+=("mmx") || true
        grep -qw 'mmxext' <<< "$flags" && detected+=("mmxext") || true
        grep -qw 'pclmulqdq' <<< "$flags" && detected+=("pclmul") || true
        grep -qw 'popcnt' <<< "$flags" && detected+=("popcnt") || true
        grep -qw 'sse' <<< "$flags" && detected+=("sse") || true
        grep -qw 'sse2' <<< "$flags" && detected+=("sse2") || true
        grep -qw 'sse3' <<< "$flags" && detected+=("sse3") || true
        grep -qw 'ssse3' <<< "$flags" && detected+=("ssse3") || true
        grep -qw 'sse4_1' <<< "$flags" && detected+=("sse4_1") || true
        grep -qw 'sse4_2' <<< "$flags" && detected+=("sse4_2") || true
        grep -qw 'sse4a' <<< "$flags" && detected+=("sse4a") || true
        grep -qw 'avx512f' <<< "$flags" && detected+=("avx512f") || true

        CPU_FLAGS_DETECTED="${detected[*]}"
    else
        CPU_FLAGS_DETECTED="$CPU_FLAGS_DEFAULT"
    fi
    log_info "Detected CPU flags: $CPU_FLAGS_DETECTED"
}

# Detect ARM CPU flags
detect_arm_cpu_flags() {
    if [[ -f /proc/cpuinfo ]]; then
        local features
        features=$(grep -m1 '^Features' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | tr -s ' ' || true)
        local detected=()

        grep -qw 'crc32' <<< "$features" && detected+=("crc") || true
        grep -qw 'aes' <<< "$features" && detected+=("crypto") || true
        grep -qw 'sha1' <<< "$features" && detected+=("crypto") || true
        grep -qw 'neon' <<< "$features" && detected+=("neon") || true
        grep -qw 'vfp' <<< "$features" && detected+=("vfp vfpv3 vfpv4 vfp-d32") || true

        CPU_FLAGS_DETECTED="${detected[*]}"
    else
        CPU_FLAGS_DETECTED="$CPU_FLAGS_DEFAULT"
    fi
    log_info "Detected CPU flags: $CPU_FLAGS_DETECTED"
}

# Build stage3 URL from mirror
build_stage3_url() {
    local mirror="$1"
    local arch="$2"
    local stage3_arch="$3"

    local base_url="${mirror}/amd64/autobuilds"
    if [[ "$arch" == "aarch64" ]]; then
        base_url="${mirror}/arm64/autobuilds"
    fi

    local stage3_dir
    stage3_dir=$(retry 3 5 curl -s "${base_url}/" | grep -oP 'stage3-${stage3_arch}-[^/]+(?=/)' | grep -v hardened | grep -v musl | head -1)

    if [[ -z "$stage3_dir" ]]; then
        die "Could not find latest stage3 for ${stage3_arch}"
    fi

    echo "${base_url}/${stage3_dir}/stage3-${stage3_arch}-${stage3_dir}.tar.zst"
}

# Get stage3 download URL
get_stage3_url() {
    if [[ -n "$STAGE3_URL" ]]; then
        log_info "Using custom stage3 URL: $STAGE3_URL"
        echo "$STAGE3_URL"
    elif [[ -n "$STAGE3_PATH" ]]; then
        log_info "Using local stage3 file: $STAGE3_PATH"
        echo "$STAGE3_PATH"
    else
        log_info "Auto-detecting stage3 from mirrors..."
        local url
        url=$(build_stage3_url "$MIRROR_URL" "$ARCH" "$STAGE3_ARCH")
        log_info "Resolved stage3 URL: $url"
        echo "$url"
    fi
}
