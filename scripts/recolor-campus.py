#!/usr/bin/env python3
"""Copy the native campus with new material colors; verify geometry byte-for-byte.

Usage: python3 scripts/recolor-campus.py --output-dir /path/to/copy
The app uses the tiny tile palette, sharing the original MeshResources in memory.
The separate .oimesh is a standalone, reversible delivery copy.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "apps/ios/OiDonation/Resources/Campus"


def unpack(path):
    packed = path.read_bytes()
    raw = bytearray(zlib.decompress(packed[4:], -15))
    assert len(raw) == struct.unpack_from("<I", packed)[0]
    assert raw[:8] == b"OICAMP07"
    return raw


def tiles(raw):
    offset = 12
    for i in range(struct.unpack_from("<I", raw, 8)[0]):
        vertices, indices = struct.unpack_from("<II", raw, offset)
        color_offset = offset + 8
        end = offset + 24 + vertices * 32 + indices * 4
        assert end <= len(raw)
        yield i, color_offset, end
        offset = end
    assert offset == len(raw)


def linear(byte):
    value = byte / 255
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    source = RESOURCES / "campus-mobile.oimesh"
    original = unpack(source)
    modified = original.copy()
    palette = json.loads(Path(__file__).with_name("campus-apricot-palette.json").read_text())
    mapping = {tuple(m["sourceLinearRGB"]): int(m["sRGB"], 16) for m in palette["materials"]}
    colors = []
    geometry = hashlib.sha256()
    for i, offset, end in tiles(original):
        rgba = struct.unpack_from("<4f", original, offset)
        rgb = mapping[tuple(round(c, 3) for c in rgba[:3])]
        colors.append(rgb)
        channels = [(rgb >> shift) & 255 for shift in (16, 8, 0)]
        struct.pack_into("<3f", modified, offset, *(linear(c) for c in channels))
        assert original[offset + 12:end] == modified[offset + 12:end]
        geometry.update(original[offset + 16:end])
    # Reverting just RGB proves no geometry, transforms, indices or alpha changed.
    reverted = modified.copy()
    for _, offset, _ in tiles(original):
        reverted[offset:offset + 12] = original[offset:offset + 12]
    assert reverted == original
    compressor = zlib.compressobj(level=6, wbits=-15)
    output = args.output_dir / "postech-campus-apricot-cream.oimesh"
    output.write_bytes(struct.pack("<I", len(modified)) + compressor.compress(modified) + compressor.flush())
    assert unpack(output) == modified
    (RESOURCES / "campus-apricot-cream.json").write_text(json.dumps(colors) + "\n")
    report = {"sourceSHA256": hashlib.sha256(source.read_bytes()).hexdigest(),
              "copySHA256": hashlib.sha256(output.read_bytes()).hexdigest(),
              "geometrySHA256": geometry.hexdigest(), "tileCount": len(colors),
              "geometryUnchanged": True, "copyBytes": output.stat().st_size,
              "paletteBytes": (RESOURCES / "campus-apricot-cream.json").stat().st_size}
    (args.output_dir / "validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
