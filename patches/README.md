# patches/ - optional core patches to the TWRP source tree

`scripts/apply-harmony-adaptation.sh` applies every `*.patch` in this directory
to the synced TWRP source with `git apply --3way`, in filename order.

This directory is empty by default on purpose. The HarmonyOS adaptation is
implemented through the device tree and the `harmony/` compatibility overlay,
which is the correct Android way to customize recovery. Core patches are only
for changes that cannot be expressed in a device tree.

If a core change becomes necessary:

1. Make it in a TWRP source checkout.
2. `git -C <twrp> diff > 0001-short-description.patch`
3. Drop the patch here and document it below.

## Patch log

_(none yet)_
