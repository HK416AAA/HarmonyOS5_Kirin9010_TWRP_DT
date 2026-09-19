# prebuilt/ - optional per-model overrides (empty for the universal build)

The universal build does **not** use this directory. It builds a kernel-less
ramdisk and relies on each device's own stock `kernel` partition for the kernel
and DTB. Nothing here ships with the tree.

Only add a file here for a **single model** whose stock kernel is missing or
cannot run TWRP userspace:

| File | Source | When |
|---|---|---|
| `kernel` | `dd if=/dev/block/by-name/kernel` | stock kernel absent/incompatible |
| `dtb.img` | `dtb`/`dts` partition, or extracted from that kernel | kernel does not self-describe |

If you add them, enable the matching lines in a **model-specific product
makefile**, never in the shared `BoardConfig.mk`, so the default build stays
universal.

Optional reference files (never built):

| File | Source |
|---|---|
| `recovery_ramdisk.img` | `dd if=/dev/block/by-name/recovery_ramdisk` |
| `recovery_vendor.img` | `dd if=/dev/block/by-name/recovery_vendor` |
