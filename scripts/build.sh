#!/bin/bash
# build.sh - build TWRP recovery and emit a HarmonyOS `recovery_ramdisk` image.
#
# Usage: SRC=/workspace/twrp ./scripts/build.sh
#
# Environment:
#   SRC            TWRP source checkout (default /workspace/twrp)
#   DEVICE         lunch target (default twrp_kirin9010)
#   VARIANT        lunch variant (default userdebug)
#   TARGET_RELEASE release config for 14.x `lunch <product>-<release>-<variant>`
#                  (default ap2a, the release shipped by AOSP android-14.0.0_r67)
#   BUILD_TARGET   build target (default recoveryimage)

# NOTE: no `set -u` here. AOSP's build/envsetup.sh references variables (TOP,
# TARGET_PRODUCT, ...) before assigning them, so nounset aborts the source.
set -eo pipefail

SRC="${SRC:-/workspace/twrp}"
DEVICE="${DEVICE:-twrp_kirin9010}"
VARIANT="${VARIANT:-userdebug}"
BUILD_TARGET="${BUILD_TARGET:-recoveryimage}"
JOB_COUNT="${JOB_COUNT:-$(nproc --all 2>/dev/null || echo 4)}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

cd "${SRC}"

echo ">>> sourcing build environment"
# shellcheck disable=SC1091
source build/envsetup.sh

# HarmonyOS/Huawei devices frequently need this during bring-up.
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL=C
export TZ=UTC

# Android 14.1 replaced `lunch <product>-<variant>` with
# `lunch <product>-<release>-<variant>` and rejects the 2-part form outright
# ("Invalid lunch combo"). Detect the newer envsetup and supply a release
# config that actually exists in the tree; older branches keep the 2-part form.
if grep -q 'product>-<release>-<variant>' build/envsetup.sh 2>/dev/null; then
    TARGET_RELEASE="${TARGET_RELEASE:-ap2a}"
    export TARGET_RELEASE
    echo ">>> lunch ${DEVICE}-${TARGET_RELEASE}-${VARIANT}"
    lunch "${DEVICE}-${TARGET_RELEASE}-${VARIANT}"
else
    echo ">>> lunch ${DEVICE}-${VARIANT}"
    lunch "${DEVICE}-${VARIANT}"
fi

echo ">>> building ${BUILD_TARGET} with ${JOB_COUNT} jobs"
# A kernel-less target can make the final boot-image step complain even though
# the recovery ramdisk was built fine. Do not abort on that; fall back to the
# ramdisk below.
if ! mka "${BUILD_TARGET}" -j"${JOB_COUNT}"; then
    echo "!!! mka ${BUILD_TARGET} returned non-zero; looking for a usable ramdisk" >&2
fi

PRODUCT_OUT="out/target/product/kirin9010"
RECOVERY_IMG="${PRODUCT_OUT}/recovery.img"

if [ ! -f "${RECOVERY_IMG}" ]; then
    echo ">>> ${RECOVERY_IMG} not found; searching for a recovery ramdisk"
    FOUND="$(find "${PRODUCT_OUT}" -maxdepth 3 -type f \
        \( -name 'recovery.img' -o -name 'ramdisk*.img' -o -name 'ramdisk-recovery*' \) \
        2>/dev/null | head -1 || true)"
    if [ -z "${FOUND}" ]; then
        # Last resort: pack the installed recovery root if it exists.
        RECOVERY_ROOT="${PRODUCT_OUT}/recovery/root"
        if [ -d "${RECOVERY_ROOT}" ] && command -v mkbootfs >/dev/null 2>&1; then
            echo ">>> packing ramdisk from ${RECOVERY_ROOT}"
            mkbootfs "${RECOVERY_ROOT}" | gzip -9 > "${HERE}/out/ramdisk.cpio.gz"
            FOUND="${HERE}/out/ramdisk.cpio.gz"
        fi
    fi
    if [ -z "${FOUND}" ]; then
        echo "!!! no recovery image or ramdisk produced; build failed" >&2
        exit 1
    fi
    RECOVERY_IMG="${FOUND}"
fi

echo ">>> recovery image: ${RECOVERY_IMG}"

mkdir -p "${HERE}/out"
if [ "${RECOVERY_IMG##*.}" = "gz" ] || [ "${RECOVERY_IMG##*.}" = "cpio" ]; then
    python3 "${HERE}/scripts/make-recovery-ramdisk.py" \
        --ramdisk "${RECOVERY_IMG}" \
        -o "${HERE}/out/recovery_ramdisk.img"
else
    python3 "${HERE}/scripts/make-recovery-ramdisk.py" \
        "${RECOVERY_IMG}" \
        -o "${HERE}/out/recovery_ramdisk.img"
fi

sha256sum "${HERE}/out/recovery_ramdisk.img" | tee "${HERE}/out/recovery_ramdisk.img.sha256"
ls -l "${HERE}/out/"
echo ">>> done"
