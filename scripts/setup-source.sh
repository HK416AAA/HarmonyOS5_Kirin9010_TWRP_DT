#!/bin/bash
# setup-source.sh - fetch the latest official TWRP source tree.
#
# TWRP is built from its official minimal AOSP manifest. The default branch is
# the newest one (twrp-14.1). Override with TWRP_BRANCH.
#
# Usage: TWRP_BRANCH=twrp-14.1 SRC=/workspace/twrp ./scripts/setup-source.sh
#
# This download is large (~20-30 GB). Run it on a machine with enough disk and
# time, e.g. a GitHub Actions runner, not a small dev sandbox.

set -euo pipefail

TWRP_BRANCH="${TWRP_BRANCH:-twrp-14.1}"
SRC="${SRC:-/workspace/twrp}"
JOB_COUNT="${JOB_COUNT:-$(nproc --all 2>/dev/null || echo 4)}"
# repo sync is network-bound, so we can run more parallel transfers than CPU
# cores. Keep the build itself at JOB_COUNT to avoid OOM on small runners.
SYNC_JOBS="${SYNC_JOBS:-$((JOB_COUNT * 2))}"
MANIFEST_URL="https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git"

echo ">>> TWRP branch : ${TWRP_BRANCH}"
echo ">>> source dir  : ${SRC}"
echo ">>> build jobs  : ${JOB_COUNT}"
echo ">>> sync jobs   : ${SYNC_JOBS}"

mkdir -p "${SRC}"
cd "${SRC}"

if ! command -v repo >/dev/null 2>&1; then
    echo ">>> installing repo tool"
    mkdir -p "${HOME}/bin"
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo \
        -o "${HOME}/bin/repo"
    chmod a+rx "${HOME}/bin/repo"
    export PATH="${HOME}/bin:${PATH}"
fi

git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "TWRP Builder"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "builder@localhost"
git config --global color.ui false

if [ -d .repo ]; then
    echo ">>> existing .repo found, reusing"
else
    # repo init --depth=1 already implies neither --partial-clone nor --no-clone-bundle;
    # --partial-clone (blob filter) is opt-in because it only pays off when the
    # build reuses the same tree and the server supports filtering.
    INIT_EXTRA=()
    if [ "${PARTIAL_CLONE:-0}" = "1" ]; then
        INIT_EXTRA+=( --partial-clone --clone-filter=blob:none )
    fi
    repo init --depth=1 --no-repo-verify \
        "${INIT_EXTRA[@]}" \
        -u "${MANIFEST_URL}" \
        -b "${TWRP_BRANCH}"
fi

# -c : current branch only, keeps the checkout small
# --no-tags / --no-clone-bundle : faster, less metadata
# --optimized-fetch : fetch each project once instead of per revision
# --prune : drop projects that are no longer in the manifest
repo sync -c -j"${SYNC_JOBS}" --force-sync --no-clone-bundle --no-tags \
    --optimized-fetch --prune

echo ">>> TWRP source ready at ${SRC}"
