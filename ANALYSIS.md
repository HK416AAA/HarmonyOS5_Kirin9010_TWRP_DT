# HMREC Recovery Image Reverse-Engineering Analysis

Source archive: `HMREC.zip` (58,720,504 bytes). Extracted originals:

- `updater_ramdisk.img` (33,554,432 bytes)
- `updater_vendor.img` (25,165,824 bytes)

## 1. Container format

Both files are raw Android boot images (`ANDROID!` magic), **header version 0**:

| Field | `updater_ramdisk.img` | `updater_vendor.img` |
|---|---|---|
| magic | `ANDROID!` | `ANDROID!` |
| kernel_size | 0 | 0 |
| kernel_addr | 0x00080000 | 0x00080000 |
| ramdisk_size | 28,266,631 | 19,232,604 |
| ramdisk_addr | 0x00100000 | 0x00100000 |
| second_size | 0 | 0 |
| second_addr | 0x00F00000 | 0x00F00000 |
| tags_addr | 0x00000100 | 0x00000100 |
| page_size | 2048 | 2048 |
| header_version | 0 | 0 |
| os_version | 0 | 0 |
| name | (empty) | (empty) |
| cmdline | `buildvariant=user` | `buildvariant=user` |
| id | all zero | all zero |
| ramdisk offset | 2048 | 2048 |

`kernel_size = 0` means these images carry **no kernel**. The ramdisk payload
begins at offset 2048 and is **gzip** compressed. Decompressed payloads are
**CPIO `newc`** archives:

- `updater_ramdisk.img.cpio` - 63,380,992 bytes, 903 entries
- `updater_vendor.img.cpio` - 51,219,968 bytes

These exact header values are reproduced by
`scripts/make-recovery-ramdisk.py` when wrapping the TWRP ramdisk.

## 2. What this actually is

This is a **HarmonyOS / OpenHarmony `updater` recovery ramdisk**, not a
bootable TWRP recovery. Evidence from the embedded parameter file
(`etc/param/ohos.para`):

```
const.updater.devicetype=pad
const.secure=1
const.debuggable=0
const.product.name="OpenHarmony 3.2"
const.product.software.version=OpenHarmony 5.0.5.165
const.product.model=ohos
const.product.manufacturer=default
const.product.brand=default
const.product.hardwareversion=default
const.product.cpu.abilist=arm64-v8a
```

`model`, `manufacturer`, `brand`, `hardwareversion` are all `default`/`ohos`,
so this is a **generic OEM updater image**, not a device-specific build. It
contains no device DTB and no device-specific kernel.

Ramdisk layout split (HarmonyOS separates what Android keeps in one boot.img):

- `updater_ramdisk.img` - root filesystem (`bin/`, `etc/`, `lib/`, `lib64/`,
  `init`, `system/`, ...)
- `updater_vendor.img` - `vendor/` tree plus vendor `lib`/`bin` binaries

Init modules under `lib64/init/`: `libselinuxadp.z.so`, `librebootmodule.z.so`,
`libhmos_update_reboot.z.so`, `libinit_manufacture.z.so`, `libudidmodule.z.so`.

Update engine libraries: `libeupdater.z.so`, `libupdater_shared.z.so`,
`libupdater_layout.z.so`, `libwpa_updater_client.z.so`.

`resources/default/progress_white_flash/*.png` are the on-screen update
animation frames (SELinux types are prefixed `aoco_`, an OEM customization).

## 3. Mount table (`etc/fstab.updater`, 672 bytes)

```
#<src>                       <mnt_point> <type> <options>                       <fs_mgr_flags>
/dev/block/by-name/misc       /misc       emmc   defaults                        defaults
/dev/block/by-name/cache      /cache      ext4   defaults                        defaults
/dev/block/by-name/userdata   /data       f2fs   defaults                        length=-16384,fileencryption=aes-256-xts:aes-256-cts,reservedsize=20M,nofail
/dev/block/by-name/splash2    /splash2    ext4   defaults                        defaults
/dev/block/mmcblk1p1          /sdcard     vfat   defaults                        defaults
/dev/block/mmcblk1            /sdcard     vfat   defaults                        defaults
/dev/block/sde1               /sdcard     vfat   defaults                        defaults
```

Key facts: `userdata` is **F2FS** with `fileencryption=aes-256-xts:aes-256-cts`
and a 20 MiB reserved size; `cache`/`splash2` are ext4; external storage is
vfat on `mmcblk1`/`sde1`.

> Note: this is the **updater's** mount table. The actual device mount table
> (`reference/fstab.Kirin9010`) differs: storage is UFS on `fa500000.ufs`,
> `system` mounts at `/usr`, product partitions are erofs, and `userdata` is
> **hmfs** with `fscrypt=1:aes-256-cts:aes-256-xts`. The device tree uses the
> real table; see `reference/README.md`.

## 4. Partition references discovered

Runtime references found by scanning both CPIO payloads for
`/dev/block/by-name/<name>`:

```
bootctrl  cache  ddr_para  dfx  flash_ageing  fw_ufsdev  hisee_fs  hisee_img
kpatch  log  misc  modem_driver  modem_fw  modem_secure  modemnvm_backup
modemnvm_cust  modemnvm_factory  modemnvm_img  modemnvm_system  modemnvm_update
nvme  nvme_bak  oeminfo  panel_calibration  reserved5  rrecord  secure_storage
sensorhub  sensorhub_log_dic  splash2  userdata
```

Candidate partition names also observed in updater config strings:

```
boot_a boot_b system_a vendor_a product_a
recovery_ramdisk recovery_vendor erecovery_ramdisk erecovery_vendor
updater_ramdisk updater_vendor modem_vendor eng_vendor eng_system vbmeta_vendor
kernel ramdisk super vbmeta dtbo dts metadata cust preload hisee xloader preas hhee
```

This matches Huawei's split-boot scheme: `kernel` (kernel + DTB) is separate
from `boot_ramdisk`/`recovery_ramdisk`/`erecovery_ramdisk`/`updater_ramdisk`,
and each `*_ramdisk` has a matching `*_vendor` part.

UFS host string `fa500000.ufs` identifies a **Kirin** SoC with UFS storage.

## 5. Storage geometry (`etc/ptable_data.json`)

```json
{
  "ptableData": {
    "emmcGptDataLen": 131072,
    "lbaLen": 512,
    "gptHeaderLen": 512,
    "blockSize": 4096,
    "imgLuSize": 17408,
    "startLunNumber": 0,
    "writeDeviceLunSize": 24576,
    "defaultLunNum": 5
  }
}
```

512-byte LBAs, 4096-byte logical blocks, 5 LUNs. Sizes here are LBA units for
the GPT writer, not final partition sizes.

## 6. Init (`etc/updater_common.cfg`)

Imports `hilogd.cfg`, `faultloggerd.cfg`, `updater_hdcd.cfg`. `pre-init`
symlinks `/system/bin` to `/bin`; `init` creates `/system`, `/vendor`, `/tmp`,
`/data`, `/param`, mounts tmpfs on `/tmp`; `post-init` creates `/sdcard` and
starts the `updater` service. A conditional job runs `/etc/lastword.sh` when
`updater.sdcard.configs=1`.

## 7. Multi-model strategy (why this is a universal build)

The images being generic is an asset. HarmonyOS splits the boot image into:

```
kernel            <- stock kernel + DTB, per model, never touched
recovery_ramdisk  <- TWRP ramdisk (this tree's output)
recovery_vendor   <- vendor ramdisk (stock or repacked)
```

The bootloader pairs the model's stock kernel with whatever ramdisk sits in
`recovery_ramdisk`. Hardware enumeration (display, touch, storage, DTB) is the
kernel's job, and each model already has the right kernel in its `kernel`
partition. So one TWRP ramdisk can serve many models:

- **Do not** bundle a kernel or DTB in the recovery tree; that would pin the
  build to a single model and remove the DTB from the bootloader's control.
- The recovery ramdisk is pure userspace (arm64), which is model-agnostic.
- Per-model differences reduce to `twrp.fstab` partition names and cosmetic
  settings; `by-name` symlinks normalize most of the naming.

Overriding a kernel/DTB is a per-model escape hatch, only for a model whose
stock kernel cannot run TWRP userspace. It belongs in a model-specific product
makefile, not in the shared tree.

## 8. How TWRP runs on HarmonyOS

TWRP is not ported into the OpenHarmony userspace. TWRP ships its own
self-contained Linux userspace (init + recovery + bionic) which runs on the
HarmonyOS **Linux kernel**. The adaptation is therefore at the boundary, not a
rewrite of TWRP:

1. **Device tree** - HarmonyOS partition names, fstab, kernel-less build.
2. **Compatibility overlay** (`harmony/`) - the Android properties and init
   nodes TWRP expects but HarmonyOS does not provide (`prop.default`,
   `init.recovery.harmony.rc`, `ueventd.harmony.rc`).
3. **Build shape** - emit a header-v0 kernel-less `recovery_ramdisk.img`
   instead of a monolithic boot.img.
4. **Optional patches** - `patches/*.patch` applied to the TWRP source when a
   core change is genuinely needed.

## 9. Consequences that still need hardware validation

1. **Kernel userspace compatibility.** TWRP recovery init needs `DEVTMPFS`,
   `BLK_DEV_INITRD`, framebuffer/DRM and input drivers in the stock kernel.
   Most OHOS kernels have these; test on the first model.
2. **64-bit only** (`abilist=arm64-v8a`), so no 32-bit secondary arch.
3. **Encryption** uses Huawei's `aes-256-xts:aes-256-cts` metadata; stock TWRP
   crypto will not open `/data` without Huawei-specific FBE support.
4. **Partition names** in `twrp.fstab` must be confirmed against the real GPT;
   the updater only references the subset it mounts.
5. **Bootloader must already be unlocked.** This analysis does not cover, and
   this tree does not implement, any bootloader unlock or security bypass.

The device tree in this repository is a scaffold built from the data above and
is deliberately kernel-less and DTB-less to stay multi-model.
