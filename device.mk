#
# Common device makefile - HarmonyOS 5 / Kirin 9010 tablets
#

LOCAL_PATH := device/huawei/kirin9010

TARGET_BOARD_API_LEVEL := 34

PRODUCT_PROPERTY_OVERRIDES += \
    ro.hardware=kirin \
    ro.board.platform=kirin \
    ro.product.device=kirin9010 \
    ro.product.board=kirin9010 \
    ro.product.cpu.abi=arm64-v8a \
    ro.product.cpu.abilist=arm64-v8a \
    ro.secure=0 \
    ro.debuggable=1 \
    ro.adb.secure=0

# Recovery fstab is installed from this tree.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/twrp.fstab:recovery/root/system/etc/recovery.fstab \
    $(LOCAL_PATH)/recovery.fstab:recovery/root/etc/recovery.fstab

# HarmonyOS compatibility overlay (props, params, extra init, ueventd).
# prop.default is generated from harmony/param/ohos.para; the .para/.dac pair
# is installed at the same path the stock OpenHarmony updater uses (etc/param).
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/harmony/prop.default:recovery/root/prop.default \
    $(LOCAL_PATH)/harmony/param/ohos.para:recovery/root/etc/param/ohos.para \
    $(LOCAL_PATH)/harmony/param/ohos.para.dac:recovery/root/etc/param/ohos.para.dac \
    $(LOCAL_PATH)/harmony/param/ohos.startup.para:recovery/root/etc/param/ohos.startup.para \
    $(LOCAL_PATH)/harmony/param/hilog.para:recovery/root/etc/param/hilog.para \
    $(LOCAL_PATH)/harmony/param/hilog.para.dac:recovery/root/etc/param/hilog.para.dac \
    $(LOCAL_PATH)/harmony/init.recovery.harmony.rc:recovery/root/etc/init/harmony.rc \
    $(LOCAL_PATH)/harmony/ueventd.harmony.rc:recovery/root/etc/init/ueventd.harmony.rc

# HarmonyOS HDC (Device Connector). hdcd is a musl/OHOS binary, so the runtime
# bundled by scripts/bundle-hdc.sh is installed under /ohos-hdc by the generated
# fragment below and run through the bundled loader (see harmony/hdc/README.md).
# Without the bundle the build still succeeds and HDC simply does not start.
# init.recovery.hdc.rc is imported from init.recovery.kirin9010.rc; it is also
# installed under the ro.hardware name so it loads whichever name init imports.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/harmony/param/hdc.para:recovery/root/etc/param/hdc.para \
    $(LOCAL_PATH)/harmony/param/hdc.para.dac:recovery/root/etc/param/hdc.para.dac \
    $(LOCAL_PATH)/harmony/hdc/hdc-usb.sh:recovery/root/sbin/hdc-usb.sh \
    $(LOCAL_PATH)/harmony/hdc/init.recovery.hdc.rc:recovery/root/init.recovery.hdc.rc \
    $(LOCAL_PATH)/init.recovery.kirin9010.rc:recovery/root/init.recovery.kirin.rc

-include $(LOCAL_PATH)/harmony/hdc/hdc-prebuilt.mk

# Vendor tree is provided prebuilt (from updater_vendor.img) or built from
# OpenHarmony sources; optional during bring-up.
-include vendor/huawei/kirin9010/AndroidVendor.mk
