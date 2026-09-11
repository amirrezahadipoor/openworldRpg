#!/usr/bin/env python3
"""Self-test for tools/check_apk.py - the release gate has to be trustworthy.

The gate exists to stop a published artefact that cannot load its own engine
binaries, so a silent bug in the gate is worse than no gate: it either blocks good
releases (what happened the first time this ran - the string-pool offsets were read
wrong and the manifest check misfired) or waves through a broken one.

These fixtures are built from scratch, in a temp dir, with no Android tooling:
a minimal binary AXML manifest and stub ``.so`` entries, in combinations that must
pass and in combinations that must fail.

Run: python3 tools/check_apk_test.py
"""

from __future__ import annotations

import io
import struct
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_apk import check  # noqa: E402

# AXML constants
XML_MAGIC = 0x0003
TYPE_STRING_POOL = 0x0001
TYPE_START_ELEMENT = 0x0102


def _string_pool(strings: list[str]) -> bytes:
    """A UTF-16 string pool chunk (the flavour aapt2 writes)."""
    encoded = [s.encode("utf-16-le") for s in strings]
    offsets = []
    blob = b""
    for enc in encoded:
        offsets.append(len(blob))
        content = struct.pack("<H", len(enc) // 2) + enc + b"\x00\x00"
        blob += content
    header_size = 28  # chunk header + count/styleCount/flags/stringsStart/stylesStart
    strings_start = header_size + 4 * len(strings)
    body = struct.pack("<IIIII", len(strings), 0, 0, strings_start, 0)
    body += b"".join(struct.pack("<I", o) for o in offsets)
    body += blob
    total = 8 + len(body)
    return struct.pack("<HHI", TYPE_STRING_POOL, header_size, total) + body


def _start_element(name_idx: int, attrs: list[tuple[int, int, int]]) -> bytes:
    """A start-element node carrying (attribute name index, raw value, typed data)."""
    attr_start, attr_size = 20, 20
    body = struct.pack("<II", 1, 0xFFFFFFFF)                 # lineNumber, comment
    body += struct.pack("<II", 0xFFFFFFFF, name_idx)          # ns, name
    # attrExt: attrStart, attrSize, attrCount, idIndex, classIndex, styleIndex
    body += struct.pack("<HHHHHH", attr_start, attr_size, len(attrs), 0, 0, 0)
    for an, raw, data in attrs:
        body += struct.pack("<IIIHBBI", 0xFFFFFFFF, an, raw, 8, 0, 0x12, data)
    total = 8 + len(body)
    return struct.pack("<HHI", TYPE_START_ELEMENT, 16, total) + body


def manifest(extract_native_libs: bool) -> bytes:
    strings = ["application", "extractNativeLibs"]
    pool = _string_pool(strings)
    node = _start_element(0, [(1, 0xFFFFFFFF, 1 if extract_native_libs else 0)])
    xml_start = struct.pack("<HHI", XML_MAGIC, 8, 8 + len(pool) + len(node))
    return xml_start + pool + node


FAKE_LIB = b"ELF" + b"\x00" * 400_000


def artifact(path: Path, *, manifest_bytes: bytes | None, name: str, method: int) -> Path:
    with zipfile.ZipFile(path, "w") as z:
        if manifest_bytes is not None:
            z.writestr(name, manifest_bytes, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("lib/arm64-v8a/libgodot_android.so", FAKE_LIB, compress_type=method)
    return path


def main() -> int:
    cases: list[tuple[str, Path, int]] = []
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        cases.append(("compressed libraries + extractable manifest", artifact(
            d / "good.apk", manifest_bytes=manifest(True), name="AndroidManifest.xml",
            method=zipfile.ZIP_DEFLATED), 0))
        cases.append(("stored libraries", artifact(
            d / "stored.apk", manifest_bytes=manifest(True), name="AndroidManifest.xml",
            method=zipfile.ZIP_STORED), 1))
        cases.append(("compressed but extractNativeLibs=false", artifact(
            d / "flag.apk", manifest_bytes=manifest(False), name="AndroidManifest.xml",
            method=zipfile.ZIP_DEFLATED), 1))
        # A bundle's manifest is protobuf, and Play rewrites it per split, so the
        # gate only asks the compression question there.
        cases.append(("bundle (protobuf manifest, compression only)", artifact(
            d / "bundle.aab", manifest_bytes=b"\x08proto\x12manifest",
            name="base/manifest/AndroidManifest.xml", method=zipfile.ZIP_DEFLATED), 0))

        failures = 0
        for label, path, want in cases:
            print(f"--- {label}")
            got = check(str(path))
            if got != want:
                print(f"SELFTEST FAIL: {label} -> exit {got}, expected {want}")
                failures += 1
        print(f"APK GATE SELFTEST: {'FAIL' if failures else 'PASS'} ({len(cases)} cases)")
        return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
