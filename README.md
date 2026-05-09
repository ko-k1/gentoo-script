# Gentoo Automated Install Script

Automated Gentoo installation with built-in optimization behaviors for amd64 and aarch64 architectures.

## Features

- **Multi-arch support**: amd64, aarch64
- **Platform-aware**: desktop, laptop, server presets with different optimizations
- **Optimization behaviors**:
  - CPU-specific CFLAGS/CXXFLAGS (`-march=native`, `-march=armv8-a+crc+crypto`)
  - Auto CPU flag detection (`CPU_FLAGS_X86`, `CPU_FLAGS_ARM`)
  - MAKEOPTS auto-tuning (`-j(N+1)` based on cores)
  - Platform-specific kernel config (laptop: ACPI, power, suspend; desktop: GPU, DRM; server: minimal)
  - Filesystem-optimized mount options (noatime, compress, commit tuning)
  - sysctl tuning (VM, scheduler, network per platform)
  - I/O scheduler optimization (bfq, mq-deadline, none)
  - CPU governor selection (performance for desktop, schedutil for laptop)
- **Acceleration**: ccache, binary packages, distcc
- **Portage sync**: git-based (default, no rsync dependency) or rsync fallback
- **Init systems**: OpenRC, systemd
- **Filesystems**: ext4, btrfs, xfs, zfs
- **Desktop environments**: GNOME, KDE, XFCE, Hyprland, Sway
- **Stage3**: Auto-detect from mirrors or custom URL/local file
- **UEFI/BIOS**: Automatic detection and configuration

## Quick Start

1. Boot a Gentoo live environment
2. Copy the script to the live environment
3. Edit `config/user.conf` with your settings (at minimum `TARGET_DISK`)
4. Run:

```bash
./install.sh --profile laptop --config config/user.conf
```

## Configuration

### Required

Edit `config/user.conf` and set at least:

```bash
TARGET_DISK="nvme0n1"  # or sda, vda, etc.
```

### Profiles

| Profile | USE flags | Kernel | Desktop | Optimizations |
|---------|-----------|--------|---------|---------------|
| `desktop` | X, audio, network | gentoo-kernel-bin | KDE + Wayland | Performance governor, responsive tuning |
| `laptop` | +laptop, +acpi, +bluetooth | gentoo-kernel-bin | KDE + Wayland | TLP, cpupower, powertop, battery tuning |
| `server` | -X, -cups, -bluetooth | gentoo-kernel-bin | None | Minimal, server-grade tuning |
| `hyprland-desktop` | X, audio, network | gentoo-kernel-bin | Hyprland + Wayland | Performance governor, responsive tuning |

### Architecture configs

| File | CFLAGS | CPU_FLAGS |
|------|--------|-----------|
| `arch/amd64.conf` | `-march=native -O2 -pipe` | aes, avx, avx2, fma3, sse*, etc. |
| `arch/aarch64.conf` | `-march=armv8-a+crc+crypto -O2 -pipe` | crc, crypto, neon, vfp* |

### Portage sync

Portage tree sync method is configured via `SYNC_TYPE`:

| Setting | Method | URI |
|---------|--------|-----|
| `git` (default) | git pull | `https://github.com/gentoo-mirror/gentoo.git` |
| `rsync` | rsync | `rsync://rsync.gentoo.org/gentoo-portage` |

git sync avoids the rsync dependency and provides delta downloads with signed commit verification.

### Platform differences

| | Desktop | Laptop |
|---|---------|--------|
| **CPU Governor** | performance | schedutil/powersave |
| **Power mgmt** | None | tlp, cpupower, powertop |
| **Thermal** | None | acpid, thermald |
| **Kernel** | GPU, DRM, FB | ACPI, battery, suspend/hibernate |
| **USE flags** | X, pulseaudio, pipewire | +laptop, +acpi, +bluetooth |
| **FS mount opts** | noatime | noatime,commit=120 (reduce writes) |
| **sysctl** | Responsive tuning | Power-efficient tuning |
| **I/O scheduler** | mq-deadline/ssd, bfq/hdd | bfq for power efficiency |

## Usage

```bash
# Install with laptop profile
./install.sh --profile laptop --config config/user.conf

# Install with desktop profile
./install.sh --profile desktop --config config/user.conf

# Install with Hyprland desktop profile
./install.sh --profile hyprland-desktop --config config/user.conf

# Dry run (show what would be done)
./install.sh --profile desktop --dry-run

# Debug mode
./install.sh --profile laptop --debug
```

## Project Structure

```
gentoo-script/
├── install.sh              # Main entry point
├── config/
│   ├── defaults.conf       # Default values
│   ├── user.conf           # User overrides (edit this)
│   └── profiles/
│       ├── desktop.conf    # Desktop preset
│       ├── laptop.conf     # Laptop preset
│       └── server.conf     # Server preset
├── lib/
│   ├── utils.sh            # Shared helpers
│   ├── arch.sh             # Arch detection + CPU flags
│   ├── stage3.sh           # Stage3 download/extract
│   ├── partition.sh        # Disk partitioning
│   ├── chroot.sh           # Chroot setup
│   ├── makeconf.sh         # make.conf generation
│   ├── portage.sh          # Portage config
│   ├── kernel.sh           # Kernel installation
│   ├── system.sh           # Bootloader, fstab, network
│   ├── accelerate.sh       # ccache, binhost, distcc
│   └── desktop.sh          # DE installation
├── arch/
│   ├── amd64.conf          # amd64 optimization flags
│   └── aarch64.conf        # aarch64 optimization flags
├── platform/
│   ├── desktop.sh          # Desktop optimizations
│   └── laptop.sh           # Laptop optimizations
└── README.md
```

## Installation Flow

1. **Pre-flight** — Load config, validate, detect arch, CPU flags
2. **Partition** — GPT partitioning (UEFI or BIOS)
3. **Stage3** — Download or use local/custom stage3
4. **Chroot** — Mount pseudo-filesystems
5. **Optimize** — Generate make.conf, set profile, USE flags
6. **Sync** — `emerge --sync` (git or rsync), update @world
7. **Kernel** — Install kernel (sources or binary)
8. **System** — Hostname, timezone, locale, fstab, bootloader
9. **Acceleration** — ccache, binhost, distcc
10. **Desktop** — Install DE + common packages
11. **Platform** — Apply governor, sysctl, scheduler, power mgmt
12. **Finalize** — Cleanup, unmount, reboot

## Requirements

- Gentoo live environment (or similar with bash, curl, tar)
- Root access
- Internet connection
- Target disk

## License

MIT
