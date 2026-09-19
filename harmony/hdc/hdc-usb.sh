#!/system/bin/sh
# hdc-usb.sh - bring up the HarmonyOS HDC (Device Connector) USB gadget and run
# the OHOS hdcd daemon inside TWRP recovery.
#
# Mirrors the official init.Kirin9010.usb.cfg:
#   FunctionFS function  ffs.hdc
#   idVendor/idProduct   0x12D1 / 0x5000
#   FunctionFS mount     /dev/usb-ffs/hdc
#   UDC                  efc00000.dwc3  (sys.usb.controller)
#
# hdcd is a musl/OHOS binary, so it is executed through the musl loader bundled
# by scripts/bundle-hdc.sh at /ohos-hdc. If that bundle is missing this script
# exits 0, so recovery still boots with no HDC.
#
# Mode comes from ro.recovery.usb.mode:
#   hdc  - HDC only (default)
#   dual - HDC plus Android adb on a second FunctionFS function
#
# The host side then uses plain `hdc` (see extract-files.sh): hdc list targets,
# hdc shell, hdc file send/recv, hdc fport/rport. HDC over TCP is also possible
# once hdcd is up (hdc tconn <device-ip>:8710).

set -u

HDC_ROOT=/ohos-hdc
LOADER="${HDC_ROOT}/lib/ld-musl-aarch64.so.1"
LIBPATH="${HDC_ROOT}/lib64:${HDC_ROOT}/lib:${HDC_ROOT}/lib64/chipset-pub-sdk:${HDC_ROOT}/lib64/platformsdk:${HDC_ROOT}/lib64/ndk"
GADGET=/config/usb_gadget/g1
CONFIG="${GADGET}/configs/b.1"
FFS=/dev/usb-ffs
MODE="$(getprop ro.recovery.usb.mode 2>/dev/null || true)"
[ -n "${MODE}" ] || MODE=hdc

log() { echo "hdc-usb: $*"; }

if [ ! -x "${HDC_ROOT}/bin/hdcd" ]; then
    log "no hdcd bundle at ${HDC_ROOT}, HDC disabled (see scripts/bundle-hdc.sh)"
    exit 0
fi

UDC="$(getprop ro.usb.controller 2>/dev/null || true)"
[ -n "${UDC}" ] || UDC=efc00000.dwc3

# 1. FunctionFS mount points (hdc always, adb additionally in dual mode).
mkdir -p "${FFS}/hdc"
mount -t functionfs hdc "${FFS}/hdc" 2>/dev/null || true
if [ "${MODE}" = "dual" ]; then
    mkdir -p "${FFS}/adb"
    mount -t functionfs adb "${FFS}/adb" 2>/dev/null || true
fi

# 2. configfs USB gadget, same descriptors as the stock USB config.
mkdir -p /config
mount -t configfs none /config 2>/dev/null || true
mkdir -p "${GADGET}"
echo 0x12D1 > "${GADGET}/idVendor"
echo 0x5000 > "${GADGET}/idProduct"
echo 0x0200 > "${GADGET}/bcdUSB"
echo 0x0224 > "${GADGET}/bcdDevice"
mkdir -p "${GADGET}/strings/0x409"
echo "HDC Device" > "${GADGET}/strings/0x409/product"
echo HISILICON   > "${GADGET}/strings/0x409/manufacturer"
if [ -r /proc/bootdevice/cid ]; then
    cat /proc/bootdevice/cid > "${GADGET}/strings/0x409/serialnumber"
fi
mkdir -p "${GADGET}/functions/ffs.hdc"
mkdir -p "${CONFIG}/strings/0x409"
echo hdc > "${CONFIG}/strings/0x409/configuration"
echo 500 > "${CONFIG}/MaxPower"

# 3. Start hdcd under the bundled musl loader and let it claim ep0.
"${LOADER}" --library-path "${LIBPATH}" "${HDC_ROOT}/bin/hdcd" \
    >/dev/null 2>&1 &
HDCD_PID=$!

# hdcd writes the FunctionFS descriptors before the gadget is bound. Wait for it
# to signal readiness via sys.usb.ffs.ready when the OHOS param shim provides
# it, otherwise fall back to a short bounded delay.
i=0
while [ "${i}" -lt 10 ]; do
    [ "$(getprop sys.usb.ffs.ready 2>/dev/null || true)" = "1" ] && break
    i=$((i + 1))
    sleep 1
done

# 4. Bind the gadget: ffs.hdc as f1 (and ffs.adb as f2 in dual mode).
ln -sf "${GADGET}/functions/ffs.hdc" "${CONFIG}/f1"
if [ "${MODE}" = "dual" ]; then
    ln -sf "${GADGET}/functions/ffs.adb" "${CONFIG}/f2"
fi
echo "${UDC}" > "${GADGET}/UDC" 2>/dev/null || log "warning: could not bind UDC ${UDC}"

setprop sys.usb.config hdc 2>/dev/null || true
setprop sys.usb.state hdc 2>/dev/null || true
setprop persist.sys.usb.config hdc 2>/dev/null || true

log "HDC up (mode=${MODE}, pid=${HDCD_PID}, udc=${UDC})"
