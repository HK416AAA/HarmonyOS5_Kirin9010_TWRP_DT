#!/usr/bin/env python3
"""hdc_extract.py - build a self-contained hdcd runtime from a stock image.

TWRP's userspace is Android/bionic. The HarmonyOS HDC daemon (`hdcd`) is a
musl/OHOS binary (`/lib/ld-musl-aarch64.so.1`, `libhilog`, `libbegetutil`,
`libutils.z`, `libcrypto_openssl.z`, ...), so TWRP cannot exec it directly.
This collects `hdcd`, the musl loader, and the transitive closure of its
NEEDED libraries from a stock OpenHarmony `updater_ramdisk` (or the same tree
extracted to a directory) into a portable bundle the recovery ramdisk can run
under the bundled loader.

Nothing proprietary is stored in the repository: run this at build time with a
stock image that you already own (see scripts/bundle-hdc.sh).

Usage:
    scripts/hdc_extract.py --image updater_ramdisk.img --out prebuilt/hdc
    scripts/hdc_extract.py --dir /path/to/extracted --out prebuilt/hdc
"""

import argparse
import gzip
import io
import os
import struct
import sys

PAGE_DEFAULT = 2048
# Prefer real SDK dirs over stray copies when a SONAME matches several paths.
PREFERRED_DIRS = ("chipset-pub-sdk", "platformsdk", "chipset-sdk", "engsdk")


# --------------------------------------------------------------------------
# Container handling
# --------------------------------------------------------------------------
def read_ramdisk(path):
    with open(path, "rb") as handle:
        blob = handle.read()
    if blob[:6] == b"070701":
        return blob
    if blob[:8] != b"ANDROID!":
        raise SystemExit(f"not an Android boot image or cpio: {path}")
    fields = struct.unpack_from("<10I", blob, 8)
    (kernel_size, _kernel_addr, ramdisk_size, _ramdisk_addr, _second_size,
     _second_addr, _tags_addr, page_size, _header_version, _os_version) = fields
    if page_size == 0:
        page_size = PAGE_DEFAULT
    rounded_kernel = (kernel_size + page_size - 1) // page_size * page_size
    offset = page_size + rounded_kernel
    return blob[offset:offset + ramdisk_size]


def gunzip(data):
    if data[:2] != b"\x1f\x8b":
        return data
    out = bytearray()
    reader = gzip.GzipFile(fileobj=io.BytesIO(data))
    while True:
        chunk = reader.read(1 << 20)
        if not chunk:
            break
        out += chunk
    return bytes(out)


def parse_cpio(buf):
    """Return {path: (mode, data)} from a newc cpio archive."""
    entries = {}
    pos = 0
    while pos + 110 <= len(buf):
        if buf[pos:pos + 6] != b"070701":
            break
        vals = [int(buf[pos + 6 + i * 8:pos + 6 + (i + 1) * 8], 16)
                for i in range(13)]
        (_, mode, _uid, _gid, _nlink, _mtime, filesize, _devmaj, _devmin,
         _rdevmaj, _rdevmin, namesize, _check) = vals
        name_off = pos + 110
        name = buf[name_off:name_off + namesize - 1].decode("utf-8", "replace")
        # newc pads the name so that header (110 B) + name is 4-byte aligned.
        name_pad = (4 - ((110 + namesize) % 4)) % 4
        data_off = name_off + namesize + name_pad
        data = buf[data_off:data_off + filesize]
        if name == "TRAILER!!!":
            break
        entries[name.rstrip("/")] = (mode, data)
        pos = data_off + (filesize + 3) // 4 * 4
    return entries


# --------------------------------------------------------------------------
# ELF handling
# --------------------------------------------------------------------------
def read_cstr(data, off):
    end = data.find(b"\0", off)
    return data[off:end].decode("utf-8", "replace")


def elf_info(data):
    """Return (needed, soname, interp) for an ELF64 file."""
    if len(data) < 64 or data[:4] != b"\x7fELF" or data[4] != 2:
        return [], None, None
    e_phoff = struct.unpack_from("<Q", data, 0x20)[0]
    e_phentsize = struct.unpack_from("<H", data, 0x36)[0]
    e_phnum = struct.unpack_from("<H", data, 0x38)[0]

    loads = []
    interp = None
    dynamic = None
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from("<I", data, off)[0]
        p_offset = struct.unpack_from("<Q", data, off + 8)[0]
        p_vaddr = struct.unpack_from("<Q", data, off + 16)[0]
        p_filesz = struct.unpack_from("<Q", data, off + 32)[0]
        if p_type == 1:                       # PT_LOAD
            loads.append((p_vaddr, p_offset, p_filesz))
        elif p_type == 3:                     # PT_INTERP
            interp = read_cstr(data, p_offset)
        elif p_type == 2:                     # PT_DYNAMIC
            dynamic = (p_offset, p_filesz)

    def vaddr_to_off(vaddr):
        for vaddr0, offset, size in loads:
            if vaddr0 <= vaddr < vaddr0 + size:
                return offset + (vaddr - vaddr0)
        return vaddr

    needed, soname = [], None
    if dynamic:
        base, size = dynamic
        raw = []
        pos = base
        while pos + 16 <= base + size:
            tag, val = struct.unpack_from("<qQ", data, pos)
            pos += 16
            if tag == 0:
                break
            raw.append((tag, val))
        strtab = next((vaddr_to_off(v) for t, v in raw if t == 5), None)
        if strtab is not None:
            for tag, val in raw:
                if tag == 1:                  # DT_NEEDED
                    needed.append(read_cstr(data, strtab + val))
                elif tag == 14:               # DT_SONAME
                    soname = read_cstr(data, strtab + val)
    return needed, soname, interp


# --------------------------------------------------------------------------
# Source abstraction (image vs directory)
# --------------------------------------------------------------------------
class ImageSource:
    def __init__(self, entries):
        self.entries = entries

    def read(self, path):
        item = self.entries.get(path)
        return item[1] if item else None

    def is_link(self, path):
        item = self.entries.get(path)
        return bool(item) and (item[0] & 0o170000) == 0o120000

    def link_target(self, path):
        data = self.read(path)
        if data is None:
            return None
        return self._resolve(os.path.dirname(path),
                             data.decode("utf-8", "replace"))

    @staticmethod
    def _resolve(dirname, target):
        if target.startswith("/"):
            return target.lstrip("/")
        return os.path.normpath(os.path.join(dirname, target))


class DirSource:
    def __init__(self, root):
        self.root = root

    def _full(self, path):
        return os.path.join(self.root, path)

    def read(self, path):
        full = self._full(path)
        if not os.path.isfile(full) or os.path.islink(full):
            return None
        with open(full, "rb") as handle:
            return handle.read()

    def is_link(self, path):
        return os.path.islink(self._full(path))

    def link_target(self, path):
        target = os.readlink(self._full(path))
        if target.startswith("/"):
            return target.lstrip("/")
        return os.path.normpath(os.path.join(os.path.dirname(path), target))


def build_index(source, entries):
    """Map basename -> best path for library lookup."""
    index = {}
    if isinstance(source, ImageSource):
        paths = list(entries)
    else:
        paths = []
        for dirpath, _dirs, files in os.walk(source.root):
            for name in files:
                full = os.path.join(dirpath, name)
                paths.append(os.path.relpath(full, source.root))
    for path in paths:
        base = os.path.basename(path)
        score = 0
        if any(d in path for d in PREFERRED_DIRS):
            score = 2
        elif path.count("/") == 1:
            score = 1
        if base not in index or score > index[base][1]:
            index[base] = (path, score)
    return index


def resolve_link(source, path):
    """Follow a chain of symlinks; return the first target that has content."""
    seen = set()
    while path not in seen:
        seen.add(path)
        if not source.is_link(path):
            return path
        target = source.link_target(path)
        if not target:
            return path
        path = target
    return path


# --------------------------------------------------------------------------
# Bundle assembly
# --------------------------------------------------------------------------
def collect(source, entries):
    bundle = {}          # relative path -> bytes
    processed = set()    # real paths whose ELF deps were already walked
    index = build_index(source, entries)

    def add(path):
        real = resolve_link(source, path)
        if source.read(real) is None:
            hit = index.get(os.path.basename(path))
            if not hit:
                print(f"warning: cannot resolve {path}", file=sys.stderr)
                return
            real = hit[0]
        data = source.read(real)
        if data is None:
            return
        # Keep the requested name too: a SONAME like libc.so may be a symlink
        # to the loader, and the dynamic linker still looks it up by name.
        bundle.setdefault(path, data)
        bundle.setdefault(real, data)
        if real in processed:
            return
        processed.add(real)
        needed, _soname, interp = elf_info(data)
        if interp:
            add(interp.lstrip("/"))
        for name in needed:
            hit = index.get(name)
            if not hit:
                print(f"warning: unresolved library {name} for {real}",
                      file=sys.stderr)
                continue
            add(hit[0])

    add("bin/hdcd")
    for extra in ("etc/param/hdc.para", "etc/param/hdc.para.dac"):
        data = source.read(extra)
        if data is not None:
            bundle[extra] = data
    return bundle


def write_bundle(bundle, out_dir):
    total = 0
    files = []
    for rel, data in sorted(bundle.items()):
        dest = os.path.join(out_dir, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as handle:
            handle.write(data)
        # hdcd and the loader are executed; libraries only need to be readable.
        base = os.path.basename(rel)
        executable = rel.startswith("bin/") or base.startswith("ld-musl")
        os.chmod(dest, 0o755 if executable else 0o644)
        total += len(data)
        files.append(rel)
        print(f"  {rel:<48} {len(data):>10}")
    return files, total


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--image", help="stock boot/ramdisk image or raw .cpio")
    src.add_argument("--dir", help="already-extracted ramdisk tree")
    ap.add_argument("--out", required=True, help="bundle output directory")
    ap.add_argument("--manifest", help="write the file list here "
                    "(default: <out>.manifest)")
    args = ap.parse_args()

    if args.image:
        source = ImageSource(parse_cpio(gunzip(read_ramdisk(args.image))))
    else:
        source = DirSource(args.dir)

    if source.read("bin/hdcd") is None:
        raise SystemExit("bin/hdcd not found in source; wrong image?")

    bundle = collect(source, getattr(source, "entries", None))
    print(f">>> hdcd runtime bundle -> {args.out}")
    files, total = write_bundle(bundle, args.out)

    manifest = args.manifest or f"{args.out}.manifest"
    with open(manifest, "w", encoding="utf-8") as handle:
        handle.write("\n".join(files) + "\n")
    print(f">>> {len(files)} files, {total / (1024 * 1024):.1f} MiB")
    print(f">>> manifest -> {manifest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
