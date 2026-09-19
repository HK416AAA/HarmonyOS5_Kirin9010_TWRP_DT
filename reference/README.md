# reference/ - official Kirin 9010 device configs

These are the vendor-supplied HarmonyOS device configuration files used to make
this device tree match the real hardware. They are the authoritative source for
the fstab, so `twrp.fstab` / `recovery.fstab` and `init.recovery.kirin9010.rc`
are derived from them.

| File | Purpose |
|---|---|
| `fstab.Kirin9010` | official mount table (partitions, fs types, mount points) |
| `init.Kirin9010.cfg` | init jobs: PATH, hardware tuning, data/hyperhold setup |
| `init.Kirin9010.usb.cfg` | USB gadget config (HDC/ADB/NCM/mass storage) |

## Key device facts taken from these files

Storage host: `fa500000.ufs`, so by-name paths are:

```
/dev/block/platform/fa500000.ufs/by-name/<name>
```

Partitions and mount points (HarmonyOS layout):

| Partition | Mount point | fs | Notes |
|---|---|---|---|
| system | `/usr` | erofs / ext4 | HarmonyOS mounts system at /usr |
| vendor | `/vendor` | erofs / ext4 | |
| sys_prod | `/sys_prod` | erofs / ext4 | required, no nofail |
| chip_prod | `/chip_prod` | erofs / ext4 | |
| cust | `/cust` | erofs / ext4 | required |
| version | `/version` | erofs / ext4 | |
| preload | `/preload` | erofs / ext4 | |
| patch | `/patch_hw` | erofs / ext4 | |
| log | `/log` | ext4 | rw |
| userdata | `/data` | **hmfs** | `fscrypt=1:aes-256-cts:aes-256-xts`, reserve_root=32768 |
| misc | `/misc` | none | |
| modem_vendor | `/vendor/modem/modem_vendor` | ext4 | |
| modem_driver | `/vendor/modem/modem_driver` | ext4 | |

Other facts:

- CPU: 8 cores across 3 clusters (`policy0`/`policy1`/`policy2`).
- GPU: `fed40000.mali`.
- RAM compression: `zram0` + HarmonyOS `hyperhold`.
- USB controller: `efc00000.dwc3`, VID `0x12D1` (Huawei), product "HDC Device".
- `/data/vendor/hyperhold` is a symlink to `/data/service/el1/0/hyperhold`.
- init `pre-init` PATH: `/usr/local/bin:/bin:/usr/bin:/system/bin:/vendor/bin`.

## Implications for TWRP

1. `twrp.fstab` uses the `fa500000.ufs` by-name path and mounts `system` at
   `/system` (TWRP requires it) even though HarmonyOS uses `/usr`.
2. `userdata` is **hmfs** with Huawei fscrypt, so TWRP will not mount or decrypt
   `/data` without hmfs + Huawei FBE support. This is expected and documented.
3. `system`/`vendor`/product partitions are **erofs** first with ext4 fallback;
   TWRP needs erofs support to read them (`TW_INCLUDE_EROFS`).
4. There is no `metadata` or `f2fs` partition on this device.
