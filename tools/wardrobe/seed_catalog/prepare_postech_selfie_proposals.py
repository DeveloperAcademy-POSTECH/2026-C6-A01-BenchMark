"""Build the five POSTECH selfie fittings from the shipped pose and donor denim.

Run: python3 tools/wardrobe/seed_catalog/prepare_postech_selfie_proposals.py . /tmp/selfie-fits
Requires NumPy, Pillow, and macOS USD tools. Output stays outside app resources.
"""
from argparse import ArgumentParser
from dataclasses import dataclass
from pathlib import Path
import io
import os
import re
import subprocess
from zipfile import ZipFile

import numpy as np
from PIL import Image, ImageChops, ImageOps

import seed_costume_geometry as geometry
from seed_costume_coverage import compact_skin, overlay_material
from seed_costume_extras import SELFIE_PARTS, selfie_fit, selfie_mask
from seed_costume_original import FACE_ARRAY
from seed_costume_skin_volume import seal_skin_cuts


BASE_NAME = "seed-costume-postech-selfie"
ALBEDO = "textures/extracted_image_1.jpg"


@dataclass(frozen=True)
class Fit:
    thigh: float
    hem: float
    depth: float


FITS = (
    Fit(0, 0, 0),          # Original straight
    Fit(-.17, -.19, -.09), # Slim straight
    Fit(.13, .13, .025),   # Relaxed straight
    Fit(.11, -.15, -.04),  # Gentle taper
    Fit(-.035, .24, .045), # Full hem
)


def donor_points(donor, original_albedo, shipped):
    """Recover the exact donor vertices for each indexed point in the shipped mesh."""
    source = geometry.read_stage(donor)
    name, points, faces, uv = next(geometry.meshes(source))
    colors = geometry.sample(original_albedo, uv.mean(axis=1)).astype(float)
    candidate = selfie_mask(points[faces].mean(axis=1), geometry.skin_color(original_albedo, uv), colors, name)
    retained = np.zeros(len(faces), dtype=bool)
    for indices, size in geometry.connected_pieces(points, faces, candidate):
        if size >= 18:
            retained[indices] = True
    faces, uv = faces[retained], uv[retained]
    authored = selfie_fit(points.copy(), faces, name)
    _, area = geometry.normals_for(authored, faces)
    valid = area > 1e-13
    used, corners = np.unique(faces[valid], return_inverse=True)
    _, installed, indices, installed_uv = shipped
    if not (np.array_equal(corners.reshape(-1, 3), indices)
            and np.allclose(uv[valid], installed_uv, rtol=0, atol=6e-8)
            and np.allclose(authored[used], installed, rtol=0, atol=6e-8)):
        raise ValueError("POSTECH selfie source no longer matches the installed pose")
    return points[used]


def denim_waist(donor, faces, uv, albedo):
    """Separate the shared jacket and denim vertices at their painted join."""
    red, green, blue = geometry.sample(albedo, uv.mean(axis=1)).astype(float).T
    neutral = 1 - geometry.smoothstep((red - green - 11) / 8)
    dark = 1 - geometry.smoothstep((np.maximum.reduce([red, green, blue]) - 83) / 50)
    heights = donor[faces, 1].mean(axis=1)
    denim = neutral * dark * (1 - geometry.smoothstep((heights - .497) / .014))
    counts = np.bincount(faces.ravel(), minlength=len(donor))
    sums = np.bincount(faces.ravel(), weights=np.repeat(denim, 3), minlength=len(donor))
    return geometry.smoothstep((sums / np.maximum(counts, 1) - .20) / .63)


def fit_denim(donor, installed, waist_material, fit):
    """Retain original rise and folds, adapting the existing jacket and shoe joins."""
    x, y, z = donor.T
    reference_x = x * 1.075
    reference_z = z * 1.10 + .012
    blend = geometry.smoothstep((y - .121) / .029)
    top = geometry.smoothstep((y - .447) / .030)
    blend *= 1 - top * (1 - waist_material)
    blend *= 1 - geometry.smoothstep((np.abs(x) - .224) / .019)

    # Ease is centered on each leg so the two shoe attachments remain in place.
    leg_center = -.014 + .117 * np.tanh((reference_x + .014) / .047)
    thigh = geometry.smoothstep((y - .169) / .245)
    width = fit.hem + (fit.thigh - fit.hem) * thigh
    profile_x = reference_x + (reference_x - leg_center) * width
    profile_z = reference_z + fit.depth * (reference_z + .067)

    # Blend the front upper cloth toward the STEP 3 jacket hem without pushing
    # the inseam down or inflating the seat against skin hidden by the costume.
    waist = geometry.smoothstep((y - .225) / .264)
    front = geometry.smoothstep((reference_z + .135) / .193)
    profile_z += .075 * waist * front
    tailored = np.column_stack((profile_x, y, profile_z))
    return installed + blend[:, None] * (tailored - installed)


def fit_mesh_block(block, installed, tailored, faces):
    """Update changed point positions and corner normals, preserving topology and UVs."""
    before, _ = geometry.normals_for(installed, faces)
    after, _ = geometry.normals_for(tailored, faces)
    normals = geometry.usd_array(block, "normals", np.float64).reshape(-1, 3)
    changed = np.any(after != before, axis=1)[faces].ravel()
    if len(normals) != len(changed):
        raise ValueError("POSTECH selfie costume is missing authored corner normals")
    normals[changed] = after[faces].reshape(-1, 3)[changed]
    arrays = {
        "points": tailored,
        "extent": [tailored.min(axis=0), tailored.max(axis=0)],
        "normals": normals,
    }

    def replace_array(match):
        prefix, name, _, suffix = match.groups()
        if name not in arrays:
            return match[0]
        return prefix[:-1] + geometry.float_array(arrays[name]) + suffix[1:]

    return FACE_ARRAY.sub(replace_array, block)


def visible_body(master):
    _, points, faces, uv = next(part for part in geometry.seed_data if part[0] == "Body")
    skin = geometry.clipped_surface(points, faces, uv, lambda p: p[:, 1] - .540)

    def inside_jacket(rim):
        center = rim.mean(axis=0)
        return center + (rim - center) * np.array([.86, 1, .86]) + np.array([0, .018, 0])

    skin = seal_skin_cuts(*skin, inside_jacket)
    material = overlay_material(geometry.read_stage(master), "VisibleBodyMaterial", "Body")
    return ("VisibleBody", *skin), material


def write_package(stage, basename, output, textures):
    stage_path = output / f"{basename}.usda"
    binary_path = stage_path.with_suffix(".usdc")
    package_path = stage_path.with_suffix(".usdz")
    stage_path.write_text(stage)
    subprocess.run(["/usr/bin/usdcat", "-o", binary_path.name, stage_path.name], cwd=output, check=True, timeout=25)
    for entry in (binary_path.name, *textures):
        os.utime(output / entry, (315532800, 315532800))
    package_path.unlink(missing_ok=True)
    subprocess.run(["/usr/bin/usdzip", package_path.name, binary_path.name, *textures],
                   cwd=output, check=True, timeout=25)
    subprocess.run(["/usr/bin/usdchecker", "--strict", "--arkit", package_path.name],
                   cwd=output, check=True, timeout=25)


def render_preview(mesh, accessory, skin, basename, output, albedo, master):
    packages = [([mesh], albedo), (accessory, np.full((4, 4, 3), (45, 43, 39), dtype=np.uint8))]
    with ZipFile(master) as archive:
        for part in (*geometry.seed_data, skin):
            name = part[0]
            if name in (*SELFIE_PARTS, "Body"):
                continue
            suffix = "BodyBaseColor" if name == "VisibleBody" else name
            image = Image.open(io.BytesIO(archive.read(f"Textures/{suffix}.png"))).convert("RGB")
            packages.append(([part], np.asarray(image)))
    geometry.raster(None, packages, basename)
    with Image.open(geometry.root / f"{basename}-0.ppm") as frame:
        background = Image.new("RGB", frame.size, frame.getpixel((0, 0)))
        bounds = ImageChops.difference(frame, background).getbbox()
        if bounds is None:
            raise ValueError(f"Missing POSTECH selfie preview for {basename}")
        thumbnail = Image.new("RGB", (129, 210), frame.getpixel((0, 0)))
        figure = ImageOps.contain(frame.crop(bounds), (121, 202), Image.Resampling.LANCZOS)
        thumbnail.paste(figure, ((thumbnail.width - figure.width) // 2, (thumbnail.height - figure.height) // 2))
        thumbnail.save(output / f"{basename}.jpg", quality=95, subsampling=0)


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("workspace", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    resources = args.workspace.resolve() / "apps/ios/OiDonation/Resources"
    output = args.output.resolve()
    if output.is_relative_to(resources):
        parser.error("output must be a staging directory outside app resources")
    geometry.configure(resources, output / ".review")
    raster = Path(__file__).with_name("raster.c")
    subprocess.run(["/usr/bin/clang", "-O3", str(raster), "-o", str(geometry.root / "raster")],
                   check=True, timeout=25)

    base = resources / "Characters" / f"{BASE_NAME}.usdz"
    master = resources / "Characters/SeedCucumberMaster.usdz"
    donor = resources / "Wardrobe/wardrobe-costume-postech-selfie.usdz"
    stage = geometry.read_stage(base)
    mesh, *accessories = geometry.meshes(stage)
    skin, material = visible_body(master)
    body = compact_skin(*skin)
    wardrobe_maps = list(dict.fromkeys(path.removeprefix("./") for path in geometry.archive.findall(stage)))
    body_maps = list(dict.fromkeys(geometry.archive.findall(material)))
    with ZipFile(base) as costume, ZipFile(master) as cucumber:
        albedo = np.asarray(Image.open(io.BytesIO(costume.read(ALBEDO))).convert("RGB"))
        for archive, entries in ((costume, wardrobe_maps), (cucumber, body_maps)):
            for entry in entries:
                path = output / entry
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(archive.read(entry))

    neutral = donor_points(donor, albedo, mesh)
    name, installed, faces, uv = mesh
    waist_material = denim_waist(neutral, faces, uv, albedo)
    mesh_block = re.search(r'(?ms)^    def Mesh "' + re.escape(name) + r'" \(.*?^    \}', stage)
    if mesh_block is None:
        raise ValueError("Missing POSTECH selfie costume mesh")
    marker = '    def Scope "Materials"\n    {\n'
    if stage.count(marker) != 1:
        raise ValueError("Missing POSTECH selfie material scope")

    render_preview(mesh, accessories, skin, "baseline", output, albedo, master)
    for number, fit in enumerate(FITS, 1):
        tailored = fit_denim(neutral, installed, waist_material, fit)
        fitted = fit_mesh_block(mesh_block[0], installed, tailored, faces)
        variant = stage[:mesh_block.start()] + fitted + stage[mesh_block.end():]
        variant = variant.replace(marker, body + marker + material, 1)
        basename = f"{BASE_NAME}-proposal-{number}"
        write_package(variant, basename, output, [*wardrobe_maps, *body_maps])
        render_preview((name, tailored, faces, uv), accessories, skin, basename, output, albedo, master)


if __name__ == "__main__":
    main()
