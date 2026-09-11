#!/usr/bin/env python3
"""Check a built Android artefact before it is published.

Two things are worth failing a release over, and both are invisible from the
outside once the file is uploaded:

1. **Are the engine binaries compressed?** An uncompressed
   ``libgodot_android.so`` is ~70 MB per ABI, and two ABIs make a side-loadable
   APK of ~175 MB - for a game whose own assets are ~25 MB. With
   ``gradle_build/compress_native_libraries=true`` the loader reads them from a
   deflated entry, which cuts the download roughly in half.
2. **Does the manifest still let Android extract them?** That only works while
   the merged manifest carries ``android:extractNativeLibs="true"``; without it
   the platform maps the library straight from the APK and a compressed entry
   fails at load, on the device, after publication.

The second check is deliberately a targeted scan rather than a full AXML parser:
it looks up the attribute name in the binary string pool and then finds the
attribute record that follows the same name index. That is enough to answer the
question a release gate needs answered ("is the flag there, and is it true"),
without a general-purpose parser in the repo.

Usage: python3 tools/check_apk.py build/OpenWorldRPG-v0.6.2.apk
Exit code 0 = publishable, 1 = do not publish.
"""

from __future__ import annotations

import re
import struct
import sys
import zipfile


def string_pool(data: bytes) -> tuple[int, int]:
    """Return (offset, count) of the first string pool chunk in an AXML file."""
    # AXML header: 0x0003 (XML), header size, file size. First chunk after it is
    # a string pool: type 0x0001, header size 0x001C.
    if len(data) < 16 or struct.unpack_from("<H", data, 0)[0] != 0x0003:
        raise ValueError("not a binary Android XML file")
    off = struct.unpack_from("<H", data, 2)[0]
    while off + 8 <= len(data):
        ctype, hsize, csize = struct.unpack_from("<HHI", data, off)
        if ctype == 0x0001:
            count = struct.unpack_from("<I", data, off + 8)[0]
            return off, count
        if csize == 0:
            break
        off += csize
    raise ValueError("no string pool chunk found")


def pool_strings(data: bytes) -> list[str]:
    """Decode every string in the pool (both UTF-8 and UTF-16 flavours)."""
    base, count = string_pool(data)
    flags, _, string_start = struct.unpack_from("<III", data, base + 8)
    utf8 = bool(flags & (1 << 8))
    offsets = [struct.unpack_from("<I", data, base + 0x1C + 4 * i)[0] for i in range(count)]
    out: list[str] = []
    for off in offsets:
        pos = base + string_start + off
        if utf8:
            # length is u8/u16, then the byte length, then the bytes
            n = data[pos]
            pos += 1
            if n & 0x80:
                n = ((n & 0x7F) << 8) | data[pos]
                pos += 1
            blen = data[pos]
            pos += 1
            if blen & 0x80:
                blen = ((blen & 0x7F) << 8) | data[pos]
                pos += 1
            out.append(data[pos:pos + blen].decode("utf-8", "replace"))
        else:
            n = struct.unpack_from("<H", data, pos)[0]
            pos += 2
            if n & 0x8000:
                n = ((n & 0x7FFF) << 16) | struct.unpack_from("<H", data, pos)[0]
                pos += 2
            out.append(data[pos:pos + 2 * n].decode("utf-16-le", "replace"))
    return out


def boolean_attribute(data: bytes, wanted: str) -> bool | None:
    """True/False if the manifest sets the named boolean attribute, else None."""
    try:
        names = pool_strings(data)
    except ValueError:
        return None
    if wanted not in names:
        return None
    index = names.index(wanted)
    # Attribute record (20 bytes): ns, name, rawValue, then a typed value
    # (size u16, res0 u8, dataType u8, data i32). TYPE_INT_BOOLEAN = 0x12.
    pattern = struct.pack("<I", index) + b"\xff\xff\xff\xff" + struct.pack("<HBBI", 8, 0, 0x12, 1)
    return pattern in data


def check(path: str) -> int:
    problems: list[str] = []
    with zipfile.ZipFile(path) as z:
        libs = [i for i in z.infolist() if i.filename.startswith("lib/") and i.filename.endswith(".so")]
        if not libs:
            # A bundle keeps them in a module rather than at the root; report it.
            libs = [i for i in z.infolist() if i.filename.endswith(".so")]
        stored = [i for i in libs if i.compress_type == zipfile.ZIP_STORED]
        deflated = [i for i in libs if i.compress_type == zipfile.ZIP_DEFLATED]
        raw_mb = sum(i.file_size for i in libs) / 1e6
        stored_mb = sum(i.compress_size for i in libs) / 1e6
        print(f"  native libraries: {len(libs)} files, {raw_mb:.1f} MB raw, {stored_mb:.1f} MB in the artefact")
        if deflated:
            saved = sum(i.file_size - i.compress_size for i in deflated) / 1e6
            print(f"  compressed: {len(deflated)} of {len(libs)} (saves {saved:.1f} MB)")
        if stored:
            problems.append(
                f"{len(stored)} native library file(s) are stored uncompressed "
                f"({sum(i.file_size for i in stored) / 1e6:.1f} MB): "
                "set gradle_build/compress_native_libraries=true"
            )

        manifest = None
        for name in z.namelist():
            if name.endswith("AndroidManifest.xml") and ("manifest" in name or name == "AndroidManifest.xml"):
                manifest = z.read(name)
                break
        if manifest is None:
            problems.append("no AndroidManifest.xml inside the artefact")
        else:
            flag = boolean_attribute(manifest, "extractNativeLibs")
            if flag is None:
                problems.append(
                    "the merged manifest does not set android:extractNativeLibs - "
                    "compressed libraries would fail to load on device"
                )
            elif not flag:
                print("  manifest: extractNativeLibs is present but false")
                problems.append("android:extractNativeLibs is false, which contradicts compressed libraries")
            else:
                print("  manifest: android:extractNativeLibs=true")

    if problems:
        for p in problems:
            print(f"APK CHECK: FAIL - {p}")
        return 1
    print(f"APK CHECK: PASS ({re.sub(r'^.*/', '', path)})")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__.strip().splitlines()[-2])
        sys.exit(2)
    sys.exit(check(sys.argv[1]))
