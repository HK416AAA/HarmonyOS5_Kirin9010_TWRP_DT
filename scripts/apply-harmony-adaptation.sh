#!/bin/bash
# apply-harmony-adaptation.sh - wire this device tree into the TWRP source and
# apply the HarmonyOS adaptation layer.
#
# What "adapting TWRP for HarmonyOS" means in practice:
#
# TWRP is not ported to the OpenHarmony userspace. TWRP ships its own
# self-contained Linux userspace (init + recovery + bionic). The device boots a
# Linux kernel (the HarmonyOS kernel), and TWRP runs on top of it. So the
# HarmonyOS-specific work lives at the boundary:
#
#   1. device tree         -> partition names, fstab, kernel-less ramdisk
#   2. compatibility layer -> Android props/init that TWRP expects but HarmonyOS
#                             does not provide (harmony/ overlay)
#   3. build shape         -> produce a header-v0 kernel-less `recovery_ramdisk`
#                             image instead of a monolithic boot.img
#   4. optional patches    -> patches/*.patch applied to the TWRP source when a
#                             core change is genuinely required
#
# Usage: SRC=/workspace/twrp ./scripts/apply-harmony-adaptation.sh

set -euo pipefail

SRC="${SRC:-/workspace/twrp}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_REL="device/huawei/kirin9010"
DEVICE_DIR="${SRC}/${DEVICE_REL}"

echo ">>> repo root  : ${HERE}"
echo ">>> TWRP source: ${SRC}"

if [ ! -d "${SRC}/build" ]; then
    echo "!!! TWRP source not found at ${SRC}; run scripts/setup-source.sh first" >&2
    exit 1
fi

# 1. Place the device tree. Symlink so CI edits to the checked-out repo are
#    picked up without copying. The whole repo root becomes the device dir;
#    .github/ and scripts/ are inert inside a device tree.
mkdir -p "$(dirname "${DEVICE_DIR}")"
if [ -L "${DEVICE_DIR}" ]; then
    ln -sfn "${HERE}" "${DEVICE_DIR}"
else
    echo ">>> copying device tree into source"
    mkdir -p "${DEVICE_DIR}"
    cp -a "${HERE}/." "${DEVICE_DIR}/"
fi
echo ">>> device tree at ${DEVICE_DIR}"

# 2. Make sure the recovery fstab/overlay files are where device.mk expects.
REQUIRED=(
    "BoardConfig.mk"
    "device.mk"
    "twrp_kirin9010.mk"
    "AndroidProducts.mk"
    "twrp.fstab"
    "recovery.fstab"
    "harmony/prop.default"
    "harmony/init.recovery.harmony.rc"
    "harmony/ueventd.harmony.rc"
)
for f in "${REQUIRED[@]}"; do
    if [ ! -e "${DEVICE_DIR}/${f}" ]; then
        echo "!!! missing required device file: ${f}" >&2
        exit 1
    fi
done
echo ">>> device tree validated"

# 3. Apply optional core patches (only if the patches/ dir has any).
shopt -s nullglob
for p in "${HERE}"/patches/*.patch; do
    echo ">>> applying core patch: $(basename "$p")"
    git -C "${SRC}" apply --3way "$p" || {
        echo "!!! failed to apply $(basename "$p")" >&2
        exit 1
    }
done
shopt -u nullglob

# 4. Report the HarmonyOS adaptation summary for the CI log.
cat <<'EOF'
>>> HarmonyOS adaptation active:
      - kernel-less ramdisk  : TARGET_NO_KERNEL := true
      - boot header geometry : v0, kernel_size=0, ramdisk@0x100000
      - fstab                : HarmonyOS by-name partition names
      - compat overlay       : prop.default + init.recovery.harmony.rc
      - crypto               : disabled (Huawei FBE unsupported)
      - post-build           : scripts/make-recovery-ramdisk.py
EOF
