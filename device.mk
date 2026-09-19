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
    $(LOCAL_PATH)/harmony/init.recovery.harmony.rc:recovery/root/etc/init/harmony.rc \
    $(LOCAL_PATH)/harmony/ueventd.harmony.rc:recovery/root/etc/init/ueventd.harmony.rc

# Vendor tree is provided prebuilt (from updater_vendor.img) or built from
# OpenHarmony sources; optional during bring-up.
-include vendor/huawei/kirin9010/AndroidVendor.mk
