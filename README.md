# HarmonyOS 5 Kirin 9010 TWRP Device Tree

TWRP device tree and CI builder for HarmonyOS 5 (OpenHarmony) Kirin 9010
tablets. Derived from reverse engineering of the OpenHarmony 5.0.5.165
`updater_ramdisk` / `updater_vendor` images. See [ANALYSIS.md](ANALYSIS.md).

## What this builds

A **kernel-less, DTB-less TWRP recovery ramdisk** for the HarmonyOS split-boot
scheme:

```
kernel            stock kernel + DTB (per model, never touched)
recovery_ramdisk  <- this project's output: TWRP, header v0, kernel_size = 0
recovery_vendor   vendor ramdisk (stock)
```

The bootloader pairs the model's stock kernel with the ramdisk in
`recovery_ramdisk`, so hardware support and the DTB come from the device. That
is what lets one ramdisk serve the whole Kirin 9010 family. Adding a kernel or
DTB here would pin the build to a single model.

## How TWRP runs on HarmonyOS

TWRP is not ported into the OpenHarmony userspace. TWRP carries its own
self-contained Linux userspace and runs on the HarmonyOS **Linux kernel**. The
HarmonyOS-specific work is a boundary adaptation, not a rewrite of TWRP:

| Layer | What it does | Where |
|---|---|---|
| Device tree | HarmonyOS partition names, fstab, kernel-less build | `*.mk`, `*.fstab` |
| Compatibility overlay | Android props/init TWRP expects, HarmonyOS lacks | `harmony/` |
| Build shape | emits a kernel-less header-v0 `recovery_ramdisk.img` | `scripts/` |
| Core patches | applied to TWRP source only when truly required | `patches/` |

## Repository layout

```
.
├── .github/workflows/build-twrp.yml   CI: sync TWRP, build, publish artifact
├── ANALYSIS.md                        image reverse-engineering report
├── BoardConfig.mk                     board config (kernel-less, geometry)
├── device.mk / twrp_kirin9010.mk      product definition
├── AndroidProducts.mk / vendorsetup.sh
├── twrp.fstab / recovery.fstab        HarmonyOS partition mount tables
├── init.recovery.kirin9010.rc         recovery init
├── harmony/                           HarmonyOS compatibility overlay
│   ├── prop.default
│   ├── init.recovery.harmony.rc
│   ├── ueventd.harmony.rc
│   └── sepolicy/recovery.te
├── scripts/
│   ├── setup-source.sh                fetch latest official TWRP source
│   ├── apply-harmony-adaptation.sh    install tree + apply overlay/patches
│   ├── build.sh                       lunch + mka + wrap ramdisk
│   └── make-recovery-ramdisk.py       kernel-less header-v0 repack
├── prebuilt/                          optional per-model overrides (empty)
└── extract-files.sh                   dump/validate partitions on device
```

## CI build (recommended)

The build needs ~30 GB of TWRP source plus build output, so it runs on GitHub
Actions. Trigger it from the **Actions** tab (`workflow_dispatch`) or by
pushing to `main`/`master`. A `v*` tag also publishes a GitHub Release with:

- `recovery_ramdisk.img`
- `recovery_ramdisk.img.sha256`

Manual dispatch lets you pick the TWRP branch (default `twrp-14.1`, the latest
official manifest).

## Local build

```bash
# 1. fetch TWRP source (~20-30 GB)
TWRP_BRANCH=twrp-14.1 SRC=/workspace/twrp ./scripts/setup-source.sh

# 2. install this tree and apply the HarmonyOS adaptation
SRC=/workspace/twrp ./scripts/apply-harmony-adaptation.sh

# 3. build and wrap the ramdisk
SRC=/workspace/twrp ./scripts/build.sh
```

Output: `out/recovery_ramdisk.img`.

## Flash

```bash
# bootloader must already be unlocked (vendor-provided)
fastboot flash recovery_ramdisk out/recovery_ramdisk.img
fastboot reboot recovery
```

The stock `kernel` partition stays untouched, so the device boots with its own
kernel and DTB.

## Verify the partition map first

The fstab partition names come from the stock updater plus the known HarmonyOS
partition set. Confirm them on your model before flashing:

```bash
adb shell su -c 'ls -l /dev/block/by-name'
```

Then reconcile `twrp.fstab`. `extract-files.sh` captures this automatically.

## Known limitations

- **Data decryption**: stock `userdata` uses Huawei FBE
  (`aes-256-xts:aes-256-cts`); stock TWRP crypto cannot open it yet.
- **Partition names**: must be validated on each model.
- **Kernel config**: the stock kernel must provide `DEVTMPFS`,
  `BLK_DEV_INITRD`, framebuffer/DRM and input drivers.
- **First boot**: set `TW_SCREEN_BLANK_ON_BOOT := false` to see kernel logs.
- **Bootloader**: must already be unlocked. This project provides no unlock or
  security-bypass capability.

## License

GPL-3.0. See [LICENSE](LICENSE).
