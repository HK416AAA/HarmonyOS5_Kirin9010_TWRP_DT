#!/usr/bin/env python3
"""
make-recovery-ramdisk.py - convert a TWRP recovery image into a HarmonyOS
`recovery_ramdisk` image.

HarmonyOS keeps the kernel and the ramdisk in separate partitions
(`kernel` and `recovery_ramdisk`). A stock TWRP `recovery.img` bundles a kernel;
flashing it to `recovery_ramdisk` is wrong. This tool strips the kernel and
emits a header-v0 image with `kernel_size = 0`, matching the geometry of the
stock `updater_ramdisk.img` exactly:

    kernel_addr  = 0x00080000
    ramdisk_addr = 0x00100000
    second_addr  = 0x00F00000
    tags_addr    = 0x00000100
    page_size    = 2048
    cmdline      = "buildvariant=user"

Usage:
    # from a built recovery.img (kernel is discarded)
    ./make-recovery-ramdisk.py out/target/product/kirin9010/recovery.img \
        -o recovery_ramdisk.img

    # from a raw ramdisk (gzip or cpio)
    ./make-recovery-ramdisk.py ramdisk.cpio -o recovery_ramdisk.img

Outputs (next to -o):
    <name>.img      flashable kernel-less recovery_ramdisk image
    <name>.ramdisk  the raw (possibly recompressed) ramdisk payload
"""

import argparse
import gzip
import os
import struct
import sys

MAGIC = b"ANDROID!"
PAGE = 2048
KERNEL_ADDR = 0x00080000
RAMDISK_ADDR = 0x00100000
SECOND_ADDR = 0x00F00000
TAGS_ADDR = 0x00000100
CMDLINE = b"buildvariant=user"


def align(value, page=PAGE):
    return (value + page - 1) // page * page


def parse_boot_image(data):
    """Return (ramdisk_bytes, page_size) from an Android boot image."""
    if data[:8] != MAGIC:
        raise SystemExit("error: input is not an Android boot image")
    if len(data) < 0x660:
        raise SystemExit("error: boot image header truncated")

    kernel_size = struct.unpack("<I", data[0x08:0x0C])[0]
    ramdisk_size = struct.unpack("<I", data[0x10:0x14])[0]
    page_size = struct.unpack("<I", data[0x24:0x28])[0]

    if page_size == 0:
        page_size = PAGE
    # v0/v1/v2 layout: header | kernel | ramdisk | second | ...
    offset = page_size
    offset += align(kernel_size, page_size)
    ramdisk = data[offset:offset + ramdisk_size]
    if len(ramdisk) != ramdisk_size:
        raise SystemExit("error: ramdisk payload truncated")
    return ramdisk, page_size


def ensure_gzip(payload):
    """Return gzip-compressed bytes; recompress if needed."""
    if payload[:2] == b"\x1f\x8b":
        return payload, False
    out = gzip.compress(payload, compresslevel=9, mtime=0)
    return out, True


def build_image(ramdisk):
    """Build a header-v0, kernel-less Android boot image."""
    header = bytearray(0x660)
    header[0x00:0x08] = MAGIC
    struct.pack_into("<I", header, 0x08, 0)                    # kernel_size
    struct.pack_into("<I", header, 0x0C, KERNEL_ADDR)
    struct.pack_into("<I", header, 0x10, len(ramdisk))         # ramdisk_size
    struct.pack_into("<I", header, 0x14, RAMDISK_ADDR)
    struct.pack_into("<I", header, 0x18, 0)                    # second_size
    struct.pack_into("<I", header, 0x1C, SECOND_ADDR)
    struct.pack_into("<I", header, 0x20, TAGS_ADDR)
    struct.pack_into("<I", header, 0x24, PAGE)                 # page_size
    struct.pack_into("<I", header, 0x28, 0)                    # header_version
    struct.pack_into("<I", header, 0x2C, 0)                    # os_version
    header[0x30:0x40] = b"\x00" * 16                           # name
    header[0x40:0x40 + len(CMDLINE)] = CMDLINE                 # cmdline
    # id (0x240) and extra_cmdline (0x260) stay zero, matching the stock
    # updater_ramdisk.img whose id field is all zeros.

    image = bytearray(align(0x660, PAGE))                      # pad to 1 page
    image[:0x660] = header
    image += ramdisk
    image += b"\x00" * (align(len(ramdisk), PAGE) - len(ramdisk))
    return bytes(image)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="recovery.img or raw ramdisk (gzip/cpio)")
    ap.add_argument("-o", "--output", default="recovery_ramdisk.img",
                    help="output image path (default: recovery_ramdisk.img)")
    ap.add_argument("--ramdisk", action="store_true",
                    help="treat input as a raw ramdisk, not an Android boot image")
    args = ap.parse_args()

    with open(args.input, "rb") as fh:
        data = fh.read()

    if args.ramdisk:
        ramdisk = data
        page = PAGE
    else:
        ramdisk, page = parse_boot_image(data)

    ramdisk, recompressed = ensure_gzip(ramdisk)
    image = build_image(ramdisk)

    base, _ = os.path.splitext(args.output)
    if not base:
        base = args.output

    with open(args.output, "wb") as fh:
        fh.write(image)
    with open(base + ".ramdisk", "wb") as fh:
        fh.write(ramdisk)

    print("input          : %s (%d bytes)" % (args.input, len(data)))
    print("page size      : %d" % page)
    print("ramdisk        : %d bytes (%s)"
          % (len(ramdisk), "recompressed to gzip" if recompressed else "already gzip"))
    print("output image   : %s (%d bytes)" % (args.output, len(image)))
    print("kernel_size    : 0 (kernel-less, matches HarmonyOS split-boot)")


if __name__ == "__main__":
    main()
