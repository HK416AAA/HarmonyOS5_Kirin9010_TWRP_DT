#!/bin/bash
# extract-files.sh - validate the partition map and optionally dump blobs.
#
# HarmonyOS is reached with HDC (Device Connector), the OpenHarmony equivalent
# of adb, so the local terminal uses `hdc shell` / `hdc file recv` by default and
# falls back to `adb` only when no HDC target is present (for example a booted
# TWRP recovery before HDC is up).
#
# The universal build needs NO kernel and NO DTB: it is a kernel-less ramdisk
# paired with each device's stock `kernel` partition, which already carries the
# kernel and its DTB. Run this to capture the partition layout so twrp.fstab can
# be verified, and optionally to grab per-model overrides.
#
# Prerequisites: developer mode enabled (hdc) or rooted device (adb), bootloader
# already unlocked. This script only reads partitions; it does not modify the
# device.
#
# Usage: ./extract-files.sh [device/dir] [--with-kernel]
#   SERIAL=<target>   select a specific hdc/adb target

set -e

DEVICE_DIR="${1:-device/huawei/kirin9010}"
WITH_KERNEL="${2:-}"
PREBUILT="${DEVICE_DIR}/prebuilt"
VENDOR_OUT="${DEVICE_DIR}/vendor_blobs"
# HarmonyOS exposes by-name under the UFS host path (see reference/fstab.Kirin9010).
BYNAME="${BYNAME:-/dev/block/platform/fa500000.ufs/by-name}"
SERIAL="${SERIAL:-}"

mkdir -p "${PREBUILT}" "${VENDOR_OUT}"

# ---------------------------------------------------------------------------
# Transport selection: HDC first, adb as fallback.
# ---------------------------------------------------------------------------
hdc_targets() { command -v hdc >/dev/null 2>&1 && hdc list targets 2>/dev/null | grep -v '^$'; }

if [ -n "$(hdc_targets)" ]; then
    TRANSPORT=hdc
    echo ">>> transport: hdc (HarmonyOS Device Connector)"
else
    TRANSPORT=adb
    echo ">>> transport: adb (no hdc target found)"
fi

dev_shell() {
    if [ "${TRANSPORT}" = hdc ]; then
        if [ -n "${SERIAL}" ]; then hdc -t "${SERIAL}" shell "$1"; else hdc shell "$1"; fi
    else
        # adb path: elevate for raw block access.
        if [ -n "${SERIAL}" ]; then adb -s "${SERIAL}" shell "su -c \"$1\""; else adb shell "su -c \"$1\""; fi
    fi
}

dev_recv() {
    local remote="$1" local_path="$2"
    if [ "${TRANSPORT}" = hdc ]; then
        if [ -n "${SERIAL}" ]; then hdc -t "${SERIAL}" file recv "${remote}" "${local_path}"; else hdc file recv "${remote}" "${local_path}"; fi
    else
        if [ -n "${SERIAL}" ]; then adb -s "${SERIAL}" pull "${remote}" "${local_path}"; else adb pull "${remote}" "${local_path}"; fi
    fi
}

if [ "${TRANSPORT}" = adb ]; then
    adb root >/dev/null 2>&1 || true
    adb wait-for-device
fi

# Fall back to the plain by-name alias if the platform path is absent.
detect_byname() {
    if dev_shell "test -d ${BYNAME}" >/dev/null 2>&1; then
        echo "${BYNAME}"
    else
        echo "/dev/block/by-name"
    fi
}

pull_partition() {
    local name="$1" out="$2"
    local base remote
    base="$(detect_byname)"
    remote="/data/local/tmp/${name}.img"
    echo ">>> dumping ${name} from ${base}"
    dev_shell "dd if=${base}/${name} of=${remote}" || {
        echo "!!! failed to dump ${name}"
        return 1
    }
    dev_recv "${remote}" "${out}" || true
    dev_shell "rm -f ${remote}" || true
}

# Capture the partition map: this is what twrp.fstab must match.
BASE="$(detect_byname)"
echo ">>> partition map from ${BASE}"
dev_shell "ls -l ${BASE}" | tee "${DEVICE_DIR}/partitions.txt"
dev_shell "cat /proc/partitions" | tee -a "${DEVICE_DIR}/partitions.txt"

# Reference ramdisks (optional, for diffing against the stock layout).
pull_partition recovery_ramdisk "${VENDOR_OUT}/recovery_ramdisk.img" || true
pull_partition recovery_vendor  "${VENDOR_OUT}/recovery_vendor.img"  || true

# Per-model override ONLY. Not needed for the universal build.
if [ "${WITH_KERNEL}" = "--with-kernel" ]; then
    echo ">>> --with-kernel: dumping per-model kernel (breaks universality)"
    pull_partition kernel "${PREBUILT}/kernel"
    pull_partition dtb    "${PREBUILT}/dtb.img" || \
        pull_partition dts "${PREBUILT}/dtb.img" || true
fi

echo ">>> done. Review ${DEVICE_DIR}/partitions.txt and fix twrp.fstab if names differ."
