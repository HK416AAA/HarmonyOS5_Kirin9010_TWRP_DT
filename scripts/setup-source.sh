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
MANIFEST_URL="https://github.com/minimal-manifest-twrp/platform_manifest_twrp_aosp.git"

echo ">>> TWRP branch : ${TWRP_BRANCH}"
echo ">>> source dir  : ${SRC}"
echo ">>> jobs        : ${JOB_COUNT}"

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
    repo init --depth=1 --no-repo-verify \
        -u "${MANIFEST_URL}" \
        -b "${TWRP_BRANCH}"
fi

# -c : current branch only, keeps the checkout small
# --no-tags / --no-clone-bundle : faster, less metadata
repo sync -c -j"${JOB_COUNT}" --force-sync --no-clone-bundle --no-tags

echo ">>> TWRP source ready at ${SRC}"
