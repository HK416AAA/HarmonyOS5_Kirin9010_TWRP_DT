#
# TWRP device tree - HarmonyOS 5 / Kirin 9010 tablets
#
# Derived from reverse engineering of the OpenHarmony 5.0.5.165
# updater_ramdisk / updater_vendor images. See ANALYSIS.md.
#
# DESIGN GOAL: one kernel-less recovery ramdisk for the whole Kirin 9010
# HarmonyOS family.
#
# HarmonyOS keeps the boot image split across three partitions:
#   kernel            stock kernel + DTB (per model, never touched)
#   recovery_ramdisk  TWRP ramdisk (this tree's output)
#   recovery_vendor   vendor ramdisk (stock)
# The bootloader pairs the stock kernel with the ramdisk in recovery_ramdisk,
# so hardware support and the DTB come from the device. This tree therefore
# builds NO kernel and NO DTB, which is what keeps it model-agnostic.
#
# Drop this tree at: device/huawei/kirin9010
# Build:             . build/envsetup.sh && lunch twrp_kirin9010-userdebug && mka recoveryimage
#

# Architecture (firmware reports abilist=arm64-v8a only)
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := generic
TARGET_2ND_ARCH :=
TARGET_SUPPORTS_64_BIT_APPS := true
TARGET_SUPPORTS_32_BIT_APPS := false

TARGET_BOARD_PLATFORM := kirin
TARGET_BOOTLOADER_BOARD_NAME := kirin9010
TARGET_NO_BOOTLOADER := true

# Kernel-less, DTB-less universal ramdisk.
TARGET_NO_KERNEL := true
BOARD_USES_GENERIC_KERNEL_IMAGE := false

# Boot image geometry, copied exactly from the stock updater image header:
#   kernel_addr=0x80000 ramdisk_addr=0x100000 second_addr=0xf00000
#   tags_addr=0x100 page_size=2048 header_version=0 os_version=0
BOARD_KERNEL_PAGESIZE := 2048
BOARD_BOOTIMG_HEADER_VERSION := 0
BOARD_KERNEL_CMDLINE := buildvariant=user
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOTIMG_HEADER_VERSION)
BOARD_MKBOOTIMG_ARGS += --pagesize $(BOARD_KERNEL_PAGESIZE)
BOARD_MKBOOTIMG_ARGS += --base 0x0
BOARD_MKBOOTIMG_ARGS += --kernel_offset 0x80000
BOARD_MKBOOTIMG_ARGS += --ramdisk_offset 0x100000
BOARD_MKBOOTIMG_ARGS += --second_offset 0xf00000
BOARD_MKBOOTIMG_ARGS += --tags_offset 0x100

# Per-model override ONLY (a model whose stock kernel cannot run TWRP).
# Put it in a model-specific product makefile, never here.
# TARGET_PREBUILT_KERNEL := device/huawei/kirin9010/prebuilt/kernel
# TARGET_PREBUILT_DTB := device/huawei/kirin9010/prebuilt/dtb.img

# Recovery
TARGET_RECOVERY_FSTAB := device/huawei/kirin9010/twrp.fstab
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TARGET_RECOVERY_DEVICE_DIRS += device/huawei/kirin9010
# HarmonyOS partitions: system/vendor/sys_prod/chip_prod/cust/version/preload/
# patch are erofs with ext4 fallback; userdata is hmfs; there is no f2fs or
# metadata partition on this device.
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_EROFS := true
TW_INCLUDE_EROFS := true
BOARD_USES_FULL_RECOVERY_IMAGE := true

# HarmonyOS split-boot is expressed with the standard AOSP knobs above:
# TARGET_NO_KERNEL makes the build emit a kernel-less header-v0 image, which is
# flashed straight to the recovery_ramdisk partition with no repacking. There is
# no BOARD_USES_HUAWEI_SPLIT_RAMDISK / BOARD_RECOVERY_*_PARTITION variable:
# AOSP and TWRP do not consume them, so setting them would only be misleading.
# The USB gadget is configfs-based on this kernel (see
# harmony/init.kirin9010.cfg), so TWRP's legacy android_usb init is excluded and
# init.rc's configfs path is selected through sys.usb.configfs.
TW_EXCLUDE_DEFAULT_USB_INIT := true

# TWRP configuration
TW_THEME := portrait_hdpi
TW_EXTRA_LANGUAGES := true
TW_DEFAULT_LANGUAGE := zh_CN
TW_SCREEN_BLANK_ON_BOOT := true
TW_USE_TOOLBOX := true
TW_INCLUDE_REPACKTOOLS := true
TW_INCLUDE_RESETPROP := true
TW_CUSTOM_CPU_TEMP_PATH := "/sys/class/thermal/thermal_zone0/temp"

# Storage
BOARD_HAS_NO_REAL_SDCARD := false
RECOVERY_SDCARD_ON_DATA := true
TW_INTERNAL_STORAGE_PATH := "/data/media/0"
TW_INTERNAL_STORAGE_MOUNT_POINT := "data"
TW_EXTERNAL_STORAGE_PATH := "/external_sd"
TW_EXTERNAL_STORAGE_MOUNT_POINT := "external_sd"

# Crypto: stock userdata is Huawei FBE (aes-256-xts:aes-256-cts). Stock TWRP
# crypto cannot decrypt it yet, so it is disabled.
TW_INCLUDE_CRYPTO := false
TW_INCLUDE_CRYPTO_FBE := false

# SELinux: HarmonyOS uses a custom policy. Start permissive.
TARGET_USES_LOGD := true
BOARD_SEPOLICY_DIRS := device/huawei/kirin9010/harmony/sepolicy
SELINUX_IGNORE_NEVERALLOWS := true

# Permissive codename assertion during bring-up.
TARGET_OTA_ASSERT_DEVICE := kirin9010,kirin,Kirin9010,ohos,HarmonyOS

BOARD_ROOT_EXTRA_FOLDERS := firmware persist
TARGET_COPY_OUT_VENDOR := vendor
