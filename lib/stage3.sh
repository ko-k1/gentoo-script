#!/usr/bin/env bash
#
# lib/stage3.sh - Stage3 download and extraction
#

# Download or copy stage3 tarball
prepare_stage3() {
    local stage3_source
    stage3_source=$(get_stage3_url)
    local stage3_filename
    stage3_filename=$(basename "$stage3_source")
    local stage3_file="${WORK_DIR}/${stage3_filename}"

    if [[ -n "$STAGE3_PATH" ]]; then
        log_info "Using local stage3: $STAGE3_PATH"
        cp "$STAGE3_PATH" "$stage3_file"
    else
        log_info "Downloading stage3: $stage3_source"

        local available
        available=$(df --output=avail -m "$WORK_DIR" 2>/dev/null | tail -1)
        if [[ -n "$available" ]] && (( available < 500 )); then
            die "Insufficient disk space in $WORK_DIR: ${available}MB available, need ~500MB"
        fi

        log_debug "Downloading URL: $stage3_source"
        retry 3 30 curl -g -L --fail -o "$stage3_file" "$stage3_source"
    fi

    if [[ ! -f "$stage3_file" ]]; then
        die "Stage3 file not found: $stage3_file"
    fi

    log_info "Stage3 ready: $stage3_file ($(du -h "$stage3_file" | cut -f1))"
}

# Extract stage3 to target
extract_stage3() {
    local stage3_source
    stage3_source=$(get_stage3_url)
    local stage3_filename
    stage3_filename=$(basename "$stage3_source")
    local stage3_file="${WORK_DIR}/${stage3_filename}"
    local target="${GENTOO_ROOT:-/mnt/gentoo}"

    ensure_dir "$target"

    log_info "Extracting stage3 to $target..."
    tar -xpf "$stage3_file" -C "$target" --xattrs-include='*.*' --numeric-owner

    log_info "Stage3 extraction complete"

    if [[ ! -d "${target}/etc" ]] || [[ ! -d "${target}/usr" ]]; then
        die "Stage3 extraction verification failed"
    fi
}

# Download and verify checksum
download_checksums() {
    local stage3_source
    stage3_source=$(get_stage3_url)
    local base_url
    base_url=$(dirname "$stage3_source")
    local stage3_filename
    stage3_filename=$(basename "$stage3_source")
    local stage3_file="${WORK_DIR}/${stage3_filename}"

    local checksum_file="${WORK_DIR}/DIGESTS"

    if [[ -n "$STAGE3_PATH" ]]; then
        log_info "Skipping checksum for local stage3"
        return
    fi

    log_info "Downloading checksums..."
    log_debug "Fetching DIGESTS from: ${base_url}/DIGESTS"
    if ! curl -sgL --fail "${base_url}/DIGESTS" -o "$checksum_file" 2>/dev/null; then
        log_warn "Checksums not available (DIGESTS not found)"
        return
    fi

    log_info "Checksums downloaded, verifying..."
    if grep -q "$stage3_filename" "$checksum_file"; then
        local expected
        expected=$(grep -A1 "$stage3_filename" "$checksum_file" | tail -1 | awk '{print $1}')
        local actual
        actual=$(sha512sum "$stage3_file" | awk '{print $1}')

        if [[ "$expected" == "$actual" ]]; then
            log_info "Stage3 checksum verified"
        else
            log_warn "Stage3 checksum mismatch (continuing anyway)"
        fi
    fi
}
