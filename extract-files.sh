#!/bin/bash
# extract-files.sh - validate the partition map and optionally dump blobs.
#
# The universal build needs NO kernel and NO DTB: it is a kernel-less ramdisk
# paired with each device's stock `kernel` partition, which already carries the
# kernel and its DTB. Run this to capture the partition layout so twrp.fstab can
# be verified, and optionally to grab per-model overrides.
#
# Prerequisites: rooted device, adb access, bootloader already unlocked.
# This script only reads partitions; it does not modify the device.
#
# Usage: ./extract-files.sh [device/dir] [--with-kernel]

set -e

DEVICE_DIR="${1:-device/huawei/kirin9010}"
WITH_KERNEL="${2:-}"
PREBUILT="${DEVICE_DIR}/prebuilt"
VENDOR_OUT="${DEVICE_DIR}/vendor_blobs"
# HarmonyOS exposes by-name under the UFS host path (see reference/fstab.Kirin9010).
BYNAME="${BYNAME:-/dev/block/platform/fa500000.ufs/by-name}"

mkdir -p "${PREBUILT}" "${VENDOR_OUT}"

adb_root() {
    adb root >/dev/null 2>&1 || true
    adb wait-for-device
    adb shell su -c "$1"
}

# Fall back to the plain by-name alias if the platform path is absent.
detect_byname() {
    if adb shell su -c "test -d ${BYNAME}" >/dev/null 2>&1; then
        echo "${BYNAME}"
    else
        echo "/dev/block/by-name"
    fi
}

pull_partition() {
    local name="$1" out="$2"
    local base
    base="$(detect_byname)"
    echo ">>> dumping ${name} from ${base}"
    adb_root "dd if=${base}/${name} of=/data/local/tmp/${name}.img" || {
        echo "!!! failed to dump ${name}"
        return 1
    }
    adb pull "/data/local/tmp/${name}.img" "${out}" || true
    adb shell "rm -f /data/local/tmp/${name}.img" || true
}

# Capture the partition map: this is what twrp.fstab must match.
BASE="$(detect_byname)"
echo ">>> partition map from ${BASE}"
adb shell su -c "ls -l ${BASE}" | tee "${DEVICE_DIR}/partitions.txt"
adb shell su -c "cat /proc/partitions"     | tee -a "${DEVICE_DIR}/partitions.txt"

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
