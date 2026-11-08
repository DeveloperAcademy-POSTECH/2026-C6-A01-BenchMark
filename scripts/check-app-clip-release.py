#!/usr/bin/env python3
"""Check an archive and the local App Clip export's thinned size report."""

import argparse
import plistlib
from pathlib import Path
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_plist(path):
    with path.open("rb") as stream:
        return plistlib.load(stream)


def check(archive, export_directory):
    apps = list((archive / "Products/Applications").glob("*.app"))
    require(len(apps) == 1, "Expected one containing app in the archive")
    app = apps[0]
    clips = list((app / "AppClips").glob("*.app"))
    require(len(clips) == 1, "Expected one embedded App Clip")
    clip = clips[0]
    app_info = read_plist(app / "Info.plist")
    clip_info = read_plist(clip / "Info.plist")
    require(clip_info["CFBundleIdentifier"] == "com.Spero.OiDonation.Clip", "Wrong Clip bundle")
    for key in ("MinimumOSVersion", "CFBundleShortVersionString", "CFBundleVersion", "UIDeviceFamily"):
        require(app_info[key] == clip_info[key], f"App/Clip mismatch: {key}")
    require(clip_info["MinimumOSVersion"] == "26.2", "Expected iOS 26.2 minimum")
    require(clip_info["UIDeviceFamily"] == [1], "Expected iPhone-only app and Clip")
    for product in (app, clip):
        require((product / "PrivacyInfo.xcprivacy").is_file(), f"Missing privacy manifest: {product.name}")
    require(any(clip.rglob("Paperlogy-OFL.txt")), "Missing Paperlogy license")
    for name in ("61272", "0e35d", "9ac42", "aeb3a"):
        require(len(list(clip.rglob(name + ".png"))) == 1, f"Missing or duplicate character: {name}")

    report = read_plist(export_directory / "app-thinning.plist")
    variants = report.get("variants", {})
    require(bool(variants), "Empty app thinning report")
    maximum = 0
    thinned_variants = 0
    for name, variant in variants.items():
        ipa_path = (export_directory / name).resolve()
        require(ipa_path.is_relative_to(export_directory.resolve()), "IPA path escapes the export directory")
        with zipfile.ZipFile(ipa_path) as ipa:
            info = plistlib.loads(ipa.read(f"Payload/{clip.name}/Info.plist"))
        for key in ("CFBundleIdentifier", "MinimumOSVersion", "CFBundleShortVersionString", "CFBundleVersion"):
            require(info[key] == clip_info[key], f"Export/archive mismatch: {key}")
        size = variant.get("sizeUncompressedApp", 0)
        require(0 < size < 15_000_000, f"Physical-invocation size budget exceeded: {name}: {size:,} bytes")
        if variant.get("variantDescriptors"):
            thinned_variants += 1
        maximum = max(maximum, size)
        print(f"PASS: {name}: {size:,} uncompressed bytes")
    require(thinned_variants > 0, "Missing thinned device variants; enable App Thinning during export")
    print(f"PASS: embedded Clip, iPhone/iOS 26.2, matching versions, privacy, license and presets; max {maximum / 1_000_000:.2f} MB")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("clip_export_directory", type=Path)
    args = parser.parse_args()
    try:
        check(args.archive, args.clip_export_directory)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, f"FAIL: {error}\n")
