#!/bin/bash
# build.sh - build TWRP recovery and emit a HarmonyOS `recovery_ramdisk` image.
#
# Usage: SRC=/workspace/twrp ./scripts/build.sh
#
# Environment:
#   SRC        TWRP source checkout (default /workspace/twrp)
#   DEVICE     lunch target (default twrp_kirin9010)
#   TARGET     build target (default recoveryimage)

set -euo pipefail

SRC="${SRC:-/workspace/twrp}"
DEVICE="${DEVICE:-twrp_kirin9010}"
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

echo ">>> lunch ${DEVICE}-userdebug"
lunch "${DEVICE}-userdebug"

echo ">>> building ${BUILD_TARGET} with ${JOB_COUNT} jobs"
mka "${BUILD_TARGET}" -j"${JOB_COUNT}"

PRODUCT_OUT="out/target/product/kirin9010"
RECOVERY_IMG="${PRODUCT_OUT}/recovery.img"

if [ ! -f "${RECOVERY_IMG}" ]; then
    echo "!!! ${RECOVERY_IMG} not found; searching for any ramdisk image" >&2
    FOUND="$(find "${PRODUCT_OUT}" -maxdepth 3 -type f \
        \( -name 'recovery.img' -o -name 'ramdisk*.img' \) 2>/dev/null | head -1 || true)"
    if [ -z "${FOUND}" ]; then
        echo "!!! no recovery image produced; build failed" >&2
        exit 1
    fi
    RECOVERY_IMG="${FOUND}"
fi

echo ">>> recovery image: ${RECOVERY_IMG}"

mkdir -p "${HERE}/out"
python3 "${HERE}/scripts/make-recovery-ramdisk.py" \
    "${RECOVERY_IMG}" \
    -o "${HERE}/out/recovery_ramdisk.img"

sha256sum "${HERE}/out/recovery_ramdisk.img" | tee "${HERE}/out/recovery_ramdisk.img.sha256"
ls -l "${HERE}/out/"
echo ">>> done"
