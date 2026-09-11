#!/usr/bin/env python3
"""Check a built Android artefact before it is published.

Two things are worth failing a release over, and both are invisible from the
outside once the file is uploaded:

1. **Are the engine binaries compressed?** An uncompressed
   ``libgodot_android.so`` is ~70 MB per ABI, and two ABIs made a side-loadable
   APK of ~175 MB for a game whose own assets are ~25 MB. With
   ``gradle_build/compress_native_libraries=true`` the same APK is ~65 MB (#91).
2. **Can Android still load them?** That only works while the merged manifest
   carries ``android:extractNativeLibs="true"``; without it the platform maps the
   library straight out of the APK, and a *compressed* entry fails at load - on a
   device, after publication, as a crash on launch. Nothing in the test suite can
   see that, which is why a release gate looks for it.

The manifest inside an APK is binary AXML, so this parses the string pool and the
``<application>`` element's attribute records. A bundle's manifest is protobuf
instead - and Play rewrites it per split - so for an ``.aab`` only the compression
question is asked, and the tool says so rather than pretending.

Usage: python3 tools/check_apk.py build/OpenWorldRPG-v0.6.2.apk
Exit code 0 = publishable, 1 = do not publish.
"""

from __future__ import annotations

import struct
import sys
import zipfile

TYPE_STRING_POOL = 0x0001
TYPE_START_ELEMENT = 0x0102
TYPE_INT_BOOLEAN = 0x12
NO_INDEX = 0xFFFFFFFF


class NotBinaryXml(ValueError):
    pass


def _string_pool(data: bytes, off: int) -> list[str]:
    """Decode an AXML string pool chunk at ``off`` (UTF-8 and UTF-16 flavours)."""
    count, _style_count, flags, strings_start = struct.unpack_from("<IIII", data, off + 8)
    utf8 = bool(flags & (1 << 8))
    out: list[str] = []
    for i in range(count):
        pos = off + strings_start + struct.unpack_from("<I", data, off + 0x1C + 4 * i)[0]
        if utf8:
            length = data[pos]
            pos += 1
            if length & 0x80:  # two-byte length
                length = ((length & 0x7F) << 8) | data[pos]
                pos += 1
            byte_len = data[pos]
            pos += 1
            if byte_len & 0x80:
                byte_len = ((byte_len & 0x7F) << 8) | data[pos]
                pos += 1
            out.append(data[pos:pos + byte_len].decode("utf-8", "replace"))
        else:
            length = struct.unpack_from("<H", data, pos)[0]
            pos += 2
            if length & 0x8000:
                length = ((length & 0x7FFF) << 16) | struct.unpack_from("<H", data, pos)[0]
                pos += 2
            out.append(data[pos:pos + 2 * length].decode("utf-16-le", "replace"))
    return out


def element_attributes(data: bytes, element: str) -> dict[str, object]:
    """Every attribute of the first ``element`` in a binary AXML document."""
    if len(data) < 16 or struct.unpack_from("<H", data, 0)[0] != 0x0003:
        raise NotBinaryXml("not a binary Android XML document")
    strings: list[str] = []
    off = struct.unpack_from("<H", data, 2)[0]
    while off + 8 <= len(data):
        ctype, _hsize, csize = struct.unpack_from("<HHI", data, off)
        if csize == 0:
            break
        if ctype == TYPE_STRING_POOL:
            strings = _string_pool(data, off)
        elif ctype == TYPE_START_ELEMENT and strings:
            name_idx = struct.unpack_from("<I", data, off + 20)[0]
            attr_start, attr_size, attr_count = struct.unpack_from("<HHH", data, off + 24)
            if name_idx < len(strings) and strings[name_idx] == element:
                found: dict[str, object] = {}
                base = off + 16 + attr_start  # attrExt starts 16 bytes into the node
                for k in range(attr_count):
                    _ns, an, raw, _size, _res0, dtype, dval = struct.unpack_from(
                        "<IIIHBBI", data, base + k * attr_size
                    )
                    if an >= len(strings):
                        continue
                    if raw != NO_INDEX and raw < len(strings):
                        found[strings[an]] = strings[raw]
                    elif dtype == TYPE_INT_BOOLEAN:
                        found[strings[an]] = bool(dval)
                    else:
                        found[strings[an]] = dval
                return found
        off += csize
    return {}


def check(path: str) -> int:
    problems: list[str] = []
    notes: list[str] = []
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        info = [(n, z.getinfo(n)) for n in names if n.endswith(".so")]
        stored = [n for n, i in info if i.compress_type == zipfile.ZIP_STORED]
        deflated = [n for n, i in info if i.compress_type == zipfile.ZIP_DEFLATED]
        raw_mb = sum(i.file_size for _, i in info) / 1e6
        packed_mb = sum(i.compress_size for _, i in info) / 1e6
        print(f"  native libraries: {len(info)} files, {raw_mb:.1f} MB raw, {packed_mb:.1f} MB in the artefact")
        if deflated:
            saved = sum(i.file_size - i.compress_size for _, i in info if i.compress_type == zipfile.ZIP_DEFLATED) / 1e6
            print(f"  compressed: {len(deflated)} of {len(info)} (saves {saved:.1f} MB)")
        if stored:
            problems.append(
                f"{len(stored)} native library file(s) are stored uncompressed "
                f"({sum(z.getinfo(n).file_size for n in stored) / 1e6:.1f} MB): "
                "set gradle_build/compress_native_libraries=true"
            )

        if "AndroidManifest.xml" in names:
            attrs = element_attributes(z.read("AndroidManifest.xml"), "application")
            flag = attrs.get("extractNativeLibs")
            print(f"  manifest: android:extractNativeLibs={flag!r}")
            if packed_mb and deflated and flag is not True:
                problems.append(
                    "libraries are compressed but the merged manifest does not set "
                    "android:extractNativeLibs=true - the app would fail to load them on device"
                )
        elif "base/manifest/AndroidManifest.xml" in names:
            notes.append(
                "bundle manifest is protobuf and Play rewrites it per split; "
                "only the compression question applies"
            )
        else:
            notes.append("no AndroidManifest.xml found in the artefact")

    for n in notes:
        print(f"  note: {n}")
    for p in problems:
        print(f"APK CHECK: FAIL - {p}")
    if problems:
        return 1
    print(f"APK CHECK: PASS ({path.rsplit('/', 1)[-1]})")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python3 tools/check_apk.py <apk-or-aab>")
        sys.exit(2)
    sys.exit(check(sys.argv[1]))
