#!/usr/bin/env bash
#
# lib/partition.sh - Disk partitioning and filesystem creation
#

# Partition disk based on config
partition_disk() {
    local disk="$1"
    local device="/dev/$disk"

    require_cmd sgdisk
    require_cmd lsblk

    if [[ ! -b "$device" ]]; then
        die "Block device not found: $device"
    fi

    log_info "Partitioning $device for ${ROOT_FS} with UEFI=$(is_uefi && echo yes || echo no)"

    if is_uefi; then
        partition_uefi "$device"
    else
        partition_bios "$device"
    fi

    log_info "Partitioning complete"
    lsblk "$device"
}

# Create GPT partitions for UEFI
partition_uefi() {
    local device="$1"
    log_info "Creating UEFI GPT partitions on $device"

    sgdisk --zap-all "$device"
    sgdisk --clear "$device"

    # EFI System Partition (512M)
    sgdisk --new=1:0:+512M --typecode=1:ef00 --change-name=1:"EFI" "$device"

    # Boot partition (1G, optional but recommended)
    sgdisk --new=2:0:+1G --typecode=2:8300 --change-name=2:"boot" "$device"

    # Root partition (rest of disk)
    sgdisk --new=3:0:0 --typecode=3:8300 --change-name=3:"root" "$device"

    # Write changes
    sgdisk --print "$device"

    # Sync
    partprobe "$device" 2>/dev/null || true
    sleep 2
}

# Create GPT partitions for BIOS
partition_bios() {
    local device="$1"
    log_info "Creating BIOS GPT partitions on $device"

    sgdisk --zap-all "$device"
    sgdisk --clear "$device"

    # BIOS Boot Partition (1M)
    sgdisk --new=1:0:+1M --typecode=1:ef02 --change-name=1:"bios_boot" "$device"

    # Boot partition (1G)
    sgdisk --new=2:0:+1G --typecode=2:8300 --change-name=2:"boot" "$device"

    # Root partition (rest of disk)
    sgdisk --new=3:0:0 --typecode=3:8300 --change-name=3:"root" "$device"

    # Write changes
    sgdisk --print "$device"

    # Sync
    partprobe "$device" 2>/dev/null || true
    sleep 2
}

# Create filesystems on partitions
create_filesystems() {
    local disk="$1"
    local fs_type="$2"

    local efi_part="/dev/${disk}1"
    local boot_part="/dev/${disk}2"
    local root_part="/dev/${disk}3"

    if is_uefi; then
        log_info "Creating FAT32 filesystem on EFI partition"
        mkfs.vfat -F 32 -n "EFI" "$efi_part"
    fi

    log_info "Creating ext4 filesystem on boot partition"
    mkfs.ext4 -L "boot" "$boot_part"

    log_info "Creating ${fs_type} filesystem on root partition"
    case "$fs_type" in
        ext4)
            mkfs.ext4 -L "root" "$root_part"
            ;;
        btrfs)
            mkfs.btrfs -L "root" "$root_part"
            ;;
        xfs)
            mkfs.xfs -L "root" "$root_part"
            ;;
        zfs)
            require_cmd zpool
            zpool create -f -O mountpoint=none -O atime=off gentoo "$root_part"
            zfs create -o mountpoint=legacy gentoo/root
            ;;
        *)
            die "Unsupported filesystem: $fs_type"
            ;;
    esac
}

# Mount partitions to gentoo root
mount_partitions() {
    local disk="$1"
    local fs_type="$2"
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    local mount_opts="${ROOT_MOUNT_OPTS_EXTRA:-}"

    local boot_part="/dev/${disk}2"
    local root_part="/dev/${disk}3"

    ensure_dir "$root"

    # Mount root
    if [[ "$fs_type" == "zfs" ]]; then
        mount -t zfs gentoo/root "$root"
    else
        if [[ -n "$mount_opts" ]]; then
            mount -o "$mount_opts" "$root_part" "$root"
        else
            mount "$root_part" "$root"
        fi
    fi

    # Create and mount boot
    ensure_dir "${root}/boot"
    mount "$boot_part" "${root}/boot"

    # Create and mount EFI
    if is_uefi; then
        local efi_part="/dev/${disk}1"
        ensure_dir "${root}/boot/efi"
        mount "$efi_part" "${root}/boot/efi"
    fi

    log_info "Partitions mounted:"
    findmnt "$root" || true
}

# Get optimized mount options for filesystem
get_fs_mount_opts() {
    local fs_type="$1"
    local platform="$2"
    local opts="defaults"

    case "$fs_type" in
        ext4)
            opts="noatime"
            if [[ "$platform" == "laptop" ]]; then
                opts="${opts},commit=120"
            fi
            ;;
        btrfs)
            opts="noatime,compress=zstd"
            if [[ "$platform" == "laptop" ]]; then
                opts="${opts},commit=120"
            fi
            ;;
        xfs)
            opts="noatime"
            ;;
        zfs)
            opts=""
            ;;
    esac

    echo "$opts"
}

# Unmount all partitions
unmount_partitions() {
    local root="${GENTOO_ROOT:-/mnt/gentoo}"
    log_info "Unmounting $root..."
    umount -R "$root" 2>/dev/null || true
    log_info "Unmounted"
}
