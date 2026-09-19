# HarmonyOS compatibility overlay

TWRP ships an Android-style userspace and expects Android properties
(`prop.default`, `ro.*`, read by its init). HarmonyOS has neither: it stores
device parameters as `.para` files that the param service reads and init
consumes through `setparam` / `param:<key>=<value>` triggers.

This directory bridges the two. Everything about device identity lives in
HarmonyOS format, and the Android side is generated from it.

## Prop handling

| File | Format | Role |
|---|---|---|
| `param/ohos.para` | HarmonyOS `.para` | **Source of truth** for device identity |
| `param/ohos.para.dac` | HarmonyOS DAC | ownership/permissions for those params |
| `param/ohos.startup.para` | HarmonyOS `.para` | `persist.sys.usb.config=hdc`, boot events |
| `param/hilog.para` + `.dac` | HarmonyOS `.para` | logging params for the bundled `libhilog.so` |
| `param/hdc.para` + `.dac` | HarmonyOS `.para` | HDC transport (USB enabled) |
| `prop.default` | Android props | **Generated** from `ohos.para`, do not edit |
| `ohos.recovery.cfg` | HarmonyOS init | reference `setparam` jobs; not used by TWRP's init |
| `init.recovery.harmony.rc` | Android init | mounts/`symlink` that TWRP's init runs |
| `ueventd.harmony.rc` | Android ueventd | device node rules ported from the stock updater |

`param/ohos.para` uses the same namespaces as the stock image
(`const.product.`, `const.build.`, `ohos.boot.`), and the `.dac` file mirrors
the stock `etc/param/ohos.para.dac` syntax:

```
<name-or-prefix>=<owner>:<group>:<mode>[:type]      # prefix ends with a dot
```

Both files are installed at `recovery/root/etc/param/`, the same path the stock
OpenHarmony updater uses.

## Why prop.default is generated

Keeping two hand-written prop files in sync is how device trees rot. Instead:

```bash
scripts/para2prop.py harmony/param/ohos.para -o harmony/prop.default
```

`scripts/apply-harmony-adaptation.sh` runs this automatically before every
build, so editing `ohos.para` is enough to change both sides.

The translation is not mechanical:

- `const.product.model` becomes `ro.product.model`, `ohos.boot.ufs` becomes
  `ro.boot.ufs`, and so on (`MAPPING` in `scripts/para2prop.py`).
- `const.secure=1` / `const.debuggable=0` describe the *secure HarmonyOS
  system*, so they are preserved as `ro.ohos.secure` / `ro.ohos.debuggable` and
  are **not** copied onto `ro.secure` / `ro.debuggable` — recovery needs those
  opposite (`0` / `1`) to allow root adb.
- Recovery-runtime values with no HarmonyOS equivalent (device codename
  `kirin9010`, USB ids, LCD density) are a static block at the end.

## What TWRP's init can and cannot do

TWRP recovery runs Android init, so the Android `.rc` files here use Android
commands (`setprop`, `mount`, `symlink`). Android init has no `setparam`, so an
OHOS `setparam` line inside a `.rc` would fail. `ohos.recovery.cfg` is kept in
HarmonyOS format for the case where OHOS init drives recovery; it is not
installed into the TWRP ramdisk.

Since recovery does not start the HarmonyOS param service, the `.para` files
are inert at runtime under TWRP. They exist so the recovery environment stays
consistent with the system it repairs, and so the device identity has one
authoritative, HarmonyOS-native definition.

## What was ported from the updater image

The stock OpenHarmony 5.0.5.165 `updater_ramdisk.img` is the runtime reference.
The following were lifted from its `etc/` tree:

- **Device nodes** — `etc/ueventd.config` became `ueventd.harmony.rc`. The stock
  file uses HarmonyOS group names; ueventd only understands Android ones, so the
  HarmonyOS-only groups are written as numeric gids from the stock `etc/group`
  (`dsoftbus=1024`, `watchdog=1100`, `camera_host=3028`, `update=6666`,
  `input=6696`, plus the Huawei media gids `1003..1006`).
- **Parameters** — `ohos.startup.para` (`persist.sys.usb.config=hdc`) and
  `hilog.para`/`.dac` join the existing `ohos.para` and `hdc.para` pairs.
- **Partition paths** — the stock `etc/fstab.updater` mounts from
  `/dev/block/by-name/*`, while the device fstab uses
  `/dev/block/platform/fa500000.ufs/by-name/*`. `init.recovery.harmony.rc`
  links the short path to the UFS path so both resolve.
- **USB / FunctionFS** — `etc/init.usb.cfg` and `etc/init.usb.configfs.cfg`
  are the basis of `hdc/init.recovery.hdc.rc` and `hdc/hdc-usb.sh`.
