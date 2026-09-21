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

# 2. Regenerate the Android properties from the HarmonyOS .para source of truth
#    so the two sides can never drift. `prop.default` is a human-readable
#    reference; `prop-overrides.mk` is what device.mk actually feeds into the
#    build (the build system owns recovery/root/prop.default and would reject a
#    second rule for it).
if [ -f "${HERE}/harmony/param/ohos.para" ]; then
    echo ">>> deriving prop.default + prop-overrides.mk from harmony/param/ohos.para"
    python3 "${HERE}/scripts/para2prop.py" \
        "${HERE}/harmony/param/ohos.para" \
        -o "${HERE}/harmony/prop.default" \
        --mk "${HERE}/harmony/prop-overrides.mk"
fi

# 3. Translate the HarmonyOS init config into the Android rc TWRP loads. The
#    .cfg files are the source of truth (see scripts/cfg2rc.py); the generated rc
#    is committed so the tree stays self-contained, and regenerated here so CI
#    always builds from the current config.
mkdir -p "${HERE}/harmony/generated"
echo ">>> generating harmony/generated/init.recovery.harmony.rc from OHOS init cfg"
python3 "${HERE}/scripts/cfg2rc.py" \
    "${HERE}/harmony/init.kirin9010.cfg" \
    "${HERE}/harmony/ohos.recovery.cfg" \
    --out "${HERE}/harmony/generated/init.recovery.harmony.rc"

# 4. Bundle the hdcd (musl) runtime when a stock image is provided. Optional:
#    without it the build still succeeds and HDC does not start.
if [ -n "${HDC_SOURCE:-}" ]; then
    echo ">>> bundling hdcd runtime from ${HDC_SOURCE}"
    "${HERE}/scripts/bundle-hdc.sh"
else
    echo ">>> HDC_SOURCE not set: building without the hdcd runtime"
fi

# 5. If the device tree was copied rather than symlinked, the generation above
#    landed in the checkout and not in the copy the build actually reads. Sync
#    the generated files across so the build never sees a stale config.
if [ "${DEVICE_DIR}" != "${HERE}" ]; then
    echo ">>> syncing generated files into ${DEVICE_DIR}"
    cp -a "${HERE}/harmony/prop.default" "${DEVICE_DIR}/harmony/prop.default"
    cp -a "${HERE}/harmony/prop-overrides.mk" "${DEVICE_DIR}/harmony/prop-overrides.mk"
    cp -a "${HERE}/harmony/generated" "${DEVICE_DIR}/harmony/"
    if [ -f "${HERE}/harmony/hdc/hdc-prebuilt.mk" ]; then
        cp -a "${HERE}/harmony/hdc/hdc-prebuilt.mk" "${DEVICE_DIR}/harmony/hdc/hdc-prebuilt.mk"
    fi
    if [ -d "${HERE}/prebuilt/hdc" ]; then
        mkdir -p "${DEVICE_DIR}/prebuilt"
        cp -a "${HERE}/prebuilt/hdc" "${DEVICE_DIR}/prebuilt/"
        if [ -f "${HERE}/prebuilt/hdc.manifest" ]; then
            cp -a "${HERE}/prebuilt/hdc.manifest" "${DEVICE_DIR}/prebuilt/hdc.manifest"
        fi
    fi
fi

# 6. Make sure the recovery fstab/overlay files are where device.mk expects.
REQUIRED=(
    "BoardConfig.mk"
    "device.mk"
    "twrp_kirin9010.mk"
    "AndroidProducts.mk"
    "twrp.fstab"
    "recovery.fstab"
    "harmony/prop.default"
    "harmony/prop-overrides.mk"
    "harmony/param/ohos.para"
    "harmony/param/ohos.para.dac"
    "harmony/param/ohos.startup.para"
    "harmony/param/hilog.para"
    "harmony/param/hilog.para.dac"
    "harmony/param/hdc.para"
    "harmony/param/hdc.para.dac"
    "harmony/hdc/init.recovery.hdc.rc"
    "harmony/hdc/hdc-usb.sh"
    "harmony/init.kirin9010.cfg"
    "harmony/ohos.recovery.cfg"
    "harmony/ueventd.config"
    "harmony/generated/init.recovery.harmony.rc"
)
for f in "${REQUIRED[@]}"; do
    if [ ! -e "${DEVICE_DIR}/${f}" ]; then
        echo "!!! missing required device file: ${f}" >&2
        exit 1
    fi
done
echo ">>> device tree validated"

# 7. Apply optional core patches (only if the patches/ dir has any).
shopt -s nullglob
for p in "${HERE}"/patches/*.patch; do
    echo ">>> applying core patch: $(basename "$p")"
    git -C "${SRC}" apply --3way "$p" || {
        echo "!!! failed to apply $(basename "$p")" >&2
        exit 1
    }
done
shopt -u nullglob

# 8. Report the HarmonyOS adaptation summary for the CI log.
cat <<'EOF'
>>> HarmonyOS adaptation active:
      - kernel-less ramdisk  : TARGET_NO_KERNEL := true
      - boot header geometry : v0, kernel_size=0, ramdisk@0x100000
      - fstab                : HarmonyOS by-name partition names
      - harmony params       : param/ohos.para (+ .dac) as source of truth
      - init config          : init.kirin9010.cfg -> generated/init.recovery.harmony.rc
      - device nodes         : ueventd.config at /system/etc (OHOS-native)
      - compat overlay       : prop-overrides.mk (derived) + thin init rc
      - HDC (Device Connector): ffs.hdc gadget + hdcd musl runtime (/ohos-hdc)
      - crypto               : disabled (Huawei FBE unsupported)
      - post-build           : scripts/make-recovery-ramdisk.py
EOF
