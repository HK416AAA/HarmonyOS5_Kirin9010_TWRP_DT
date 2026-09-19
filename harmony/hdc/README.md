# HDC (HarmonyOS Device Connector) in recovery

HDC is HarmonyOS's device bridge, the equivalent of adb: `hdc shell`,
`hdc file send/recv`, `hdc fport/rport`, `hdc list targets`, and so on. TWRP
cannot provide it out of the box because HDC is not an Android protocol and its
device daemon is not an Android binary.

## Why hdcd is bundled instead of built

The stock `hdcd` is a **musl/OHOS** binary:

```
interpreter : /lib/ld-musl-aarch64.so.1
NEEDED      : libhilog.so libsec_shared.z.so libutils.z.so libbegetutil.z.so
              libuv.so libcrypto_openssl.z.so libselinux.z.so libc.so libc++.so
```

TWRP's userspace is Android/bionic (`/system/bin/linker64`), which cannot load
it. Rather than port the daemon, `scripts/bundle-hdc.sh` copies `hdcd`, the musl
loader and the transitive closure of its libraries out of a stock OpenHarmony
image you already own, and recovery runs it through the bundled loader. The
result is about 12 MiB under `/ohos-hdc`:

```
/ohos-hdc/bin/hdcd
/ohos-hdc/lib/ld-musl-aarch64.so.1
/ohos-hdc/lib64/...            (chipset-pub-sdk / platformsdk / ndk libs)
/ohos-hdc/etc/param/hdc.para
```

Nothing proprietary is committed: `prebuilt/hdc/` is git-ignored and the list of
files that get installed is generated into `harmony/hdc/hdc-prebuilt.mk` (also
git-ignored, since it references those files). Without a bundle the `-include`
in `device.mk` finds nothing and HDC is simply absent.

## Building the bundle

```bash
HDC_SOURCE=updater_ramdisk.img ./scripts/bundle-hdc.sh
# or an already-extracted ramdisk tree:
HDC_SOURCE=/path/to/extracted-ramdisk ./scripts/bundle-hdc.sh
```

`scripts/hdc_extract.py` accepts a boot image, a raw `.cpio`, or a directory. It
resolves the ELF `NEEDED` closure and fails loudly on any library it cannot find,
so an incomplete bundle is never produced. `scripts/apply-harmony-adaptation.sh`
runs the bundler automatically when `HDC_SOURCE` is set.

## USB wiring

`init.recovery.hdc.rc` starts `hdc-usb.sh` on boot. `hdc-usb.sh` mirrors the
official `reference/init.Kirin9010.usb.cfg`:

| Item | Value |
|---|---|
| FunctionFS function | `ffs.hdc` |
| idVendor / idProduct | `0x12D1` / `0x5000` |
| FunctionFS mount | `/dev/usb-ffs/hdc` |
| UDC | `efc00000.dwc3` (`ro.usb.controller`) |
| Configuration | `hdc` |

`ro.recovery.usb.mode` selects the transport: `hdc` (default) or `dual` (HDC
plus Android adb on `ffs.adb`). Without the bundle, `hdc-usb.sh` exits 0 and
recovery boots normally with no HDC.

## Host usage

```bash
hdc list targets
hdc shell
hdc file send local.img /data/local/tmp/local.img
hdc file recv /data/local/tmp/dump.img ./dump.img
hdc fport tcp:1234 tcp:1234
```

HDC over TCP is possible once `hdcd` is running, which avoids USB entirely:

```bash
hdc tconn <device-ip>:8710
```

## Limitations

- **No OHOS param service in recovery.** `hdcd` reads and writes params through
  OpenHarmony's param service, which TWRP does not run. `hdc.para`/`hdc.para.dac`
  are installed in HarmonyOS format for consistency, and `hdc-usb.sh` sets the
  Android props instead, but the `sys.usb.ffs.ready` handshake may never arrive.
  The script therefore also has a bounded-delay fallback before binding the UDC.
- **`libbegetutil` expects OHOS init.** Some daemon features (parameter access,
  beget/init calls) may log errors or be unavailable; basic shell and file
  transfer are handled by `hdcd` itself and do not depend on OHOS services.
- **Requires the stock kernel to provide the HDC gadget.** The FunctionFS
  function and the `efc00000.dwc3` controller come from the HarmonyOS kernel; if
  a model's kernel lacks them, only the TCP path can work.
- **Needs on-device validation.** The wiring is derived from the official configs
  but has not been exercised on hardware; expect to tune the readiness handshake.
