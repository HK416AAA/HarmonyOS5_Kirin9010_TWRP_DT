#
# Common device makefile - HarmonyOS 5 / Kirin 9010 tablets
#

LOCAL_PATH := device/huawei/kirin9010

TARGET_BOARD_API_LEVEL := 34

# Android properties (ro.hardware, ro.product.*, ro.secure, ro.ohos.*, ...) are
# all derived from harmony/param/ohos.para by scripts/para2prop.py and included
# from harmony/prop-overrides.mk below. ohos.para is the single source of truth.

# Recovery fstab is installed from this tree. Everything under /etc in the
# recovery root must be installed below system/etc: the ramdisk root has
# `etc -> /system/etc`, and writing to recovery/root/etc/ directly creates a
# real directory there, which makes the ramdisk-assembly rsync fail with
# "could not make way for new symlink: root/etc".
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/twrp.fstab:recovery/root/system/etc/recovery.fstab \
    $(LOCAL_PATH)/recovery.fstab:recovery/root/system/etc/recovery-aosp.fstab

# HarmonyOS compatibility overlay (props, params, extra init, ueventd).
# The .para/.dac pair is installed at the same path the stock OpenHarmony
# updater uses (etc/param). The Android properties derived from ohos.para are
# injected through the generated fragment below, not copied: the build system
# owns recovery/root/prop.default and a second rule for it is an error.
-include $(LOCAL_PATH)/harmony/prop-overrides.mk

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/harmony/param/ohos.para:recovery/root/system/etc/param/ohos.para \
    $(LOCAL_PATH)/harmony/param/ohos.para.dac:recovery/root/system/etc/param/ohos.para.dac \
    $(LOCAL_PATH)/harmony/param/ohos.startup.para:recovery/root/system/etc/param/ohos.startup.para \
    $(LOCAL_PATH)/harmony/param/hilog.para:recovery/root/system/etc/param/hilog.para \
    $(LOCAL_PATH)/harmony/param/hilog.para.dac:recovery/root/system/etc/param/hilog.para.dac \
    $(LOCAL_PATH)/harmony/ueventd.config:recovery/root/system/etc/ueventd.config

# HarmonyOS init config is the source of truth; the Android rc TWRP actually
# loads is generated from it by scripts/cfg2rc.py. See init.recovery.kirin9010.rc.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/harmony/generated/init.recovery.harmony.rc:recovery/root/init.recovery.harmony.rc

# HarmonyOS HDC (Device Connector). hdcd is a musl/OHOS binary, so the runtime
# bundled by scripts/bundle-hdc.sh is installed under /ohos-hdc by the generated
# fragment below and run through the bundled loader (see harmony/hdc/README.md).
# Without the bundle the build still succeeds and HDC simply does not start.
# init.recovery.hdc.rc is imported from init.recovery.kirin9010.rc.
# The recovery init rc is installed under both ro.hardware names: init imports
# `/init.recovery.${ro.hardware}.rc` and the property may be kirin or kirin9010.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/harmony/param/hdc.para:recovery/root/system/etc/param/hdc.para \
    $(LOCAL_PATH)/harmony/param/hdc.para.dac:recovery/root/system/etc/param/hdc.para.dac \
    $(LOCAL_PATH)/harmony/hdc/hdc-usb.sh:recovery/root/sbin/hdc-usb.sh \
    $(LOCAL_PATH)/harmony/hdc/init.recovery.hdc.rc:recovery/root/init.recovery.hdc.rc \
    $(LOCAL_PATH)/init.recovery.kirin9010.rc:recovery/root/init.recovery.kirin.rc \
    $(LOCAL_PATH)/init.recovery.kirin9010.rc:recovery/root/init.recovery.kirin9010.rc

-include $(LOCAL_PATH)/harmony/hdc/hdc-prebuilt.mk

# Vendor tree is provided prebuilt (from updater_vendor.img) or built from
# OpenHarmony sources; optional during bring-up.
-include vendor/huawei/kirin9010/AndroidVendor.mk
