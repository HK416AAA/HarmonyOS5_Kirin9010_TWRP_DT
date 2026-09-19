#
# TWRP product definition - HarmonyOS 5 / Kirin 9010 tablets
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/languages_full.mk)

$(call inherit-product, device/huawei/kirin9010/device.mk)
$(call inherit-product, vendor/twrp/config/common.mk)

PRODUCT_NAME := twrp_kirin9010
PRODUCT_DEVICE := kirin9010
PRODUCT_BRAND := huawei
PRODUCT_MODEL := HarmonyOS Kirin 9010
PRODUCT_MANUFACTURER := HUAWEI
PRODUCT_RELEASE_NAME := kirin9010

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRODUCT_DEVICE=kirin9010 \
    PRODUCT_NAME=kirin9010 \
    TARGET_DEVICE=kirin9010
