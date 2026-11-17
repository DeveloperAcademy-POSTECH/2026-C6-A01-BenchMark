"""Build the three STEP 3 comparison models for each of the six selected outfits."""
import argparse
import io
from pathlib import Path
import re
import subprocess
from zipfile import ZipFile

import numpy as np
from PIL import Image

import seed_costume_geometry as geometry
from seed_costume_hood_interior import seal_hood_face
from seed_costume_original import FACE_ARRAY, overlay_material
from seed_costume_rigid_hoods import PROFILE, STEM_OFFSETS, aperture
from seed_costume_scientist_original import collar_coords, collar_ring, keep_scientist

COSTUMES = ("raincoat", "astronaut", "scientist", "cat-bear", "postech-selfie", "astronaut-navy")
STEMS = {**STEM_OFFSETS, "cat-bear": (-.036, -.064, -.066), "raincoat": (-.018, -.052, .012)}
SKIN_PATH = "/SeedCostume/Materials/VisibleBodyMaterial"


def hood_fit(costume, points, index):
    x, y, z = points.T
    fitted = points.copy()
    if costume in PROFILE:
        width, depth, crown = ((.018, .025, 0), (-.075, -.105, -.017), (.10, .145, .012))[index]
        height = geometry.smoothstep((y - .910) / .105)
        stem = geometry.smoothstep((np.hypot(x, z + .036) - .075) / .095)
        side = height * stem * (1 - geometry.smoothstep((z - .045) / .058))
        fitted[:, 0] += x * side * width
        fitted[:, 2] += np.minimum(z + .005, 0) * height * stem * depth
        fitted[:, 1] += geometry.smoothstep((y - 1.19) / .112) * side * crown
    elif costume == "cat-bear":
        radius = np.hypot((x + .004) / .204, (y - 1.019) / .219)
        rim = 1 - geometry.smoothstep((radius - 1.05) / .37)
        front = geometry.smoothstep((z - .016) / .065) * (1 - geometry.smoothstep((z - .193) / .067))
        crown = 1 - geometry.smoothstep((y - 1.163) / .106)
        neck = geometry.smoothstep((y - .738) / .090)
        cheek = .029 + .036 * np.exp(-((y - 1.012) / .128) ** 2)
        fitted[:, 2] += rim * front * crown * neck * cheek
        shell = geometry.smoothstep((y - .83) / .13) * (1 - geometry.smoothstep((z - .065) / .13))
        width, depth, top = ((0, 0, 0), (.09, .14, 0), (.015, .035, .034))[index]
        fitted[:, 0] += x * shell * width
        fitted[:, 2] += np.minimum(z, 0) * shell * depth
        fitted[:, 1] += top * shell * geometry.smoothstep((y - 1.07) / .19)
    else:
        brim, depth = ((.012, .018), (.083, .030), (.035, .24))[index]
        height = geometry.smoothstep((y - .89) / .15)
        front = geometry.smoothstep((z - .025) / .09)
        crown = np.exp(-((y - 1.235) / .106) ** 2)
        fitted[:, 2] += brim * height * front * crown
        fitted[:, 2] += depth * np.minimum(z, 0) * height
        fitted[:, 0] += x * front * height * crown * (0, .10, .035)[index]
    return fitted


def fit_neckline(points, index):
    x, y, z = points.T
    height = geometry.smoothstep((y - .69) / .145) * (1 - geometry.smoothstep((y - .975) / .029))
    near_center = 1 - geometry.smoothstep((abs(x + .009) - .202) / .037)
    fitted = points.copy()
    clearance = fitted.copy()
    geometry.body.push_out(clearance, .018)
    fitted[:, [0, 2]] += (clearance[:, [0, 2]] - fitted[:, [0, 2]]) * (height * near_center)[:, None]
    front = geometry.smoothstep((z - .06) / .08)
    middle = np.exp(-(x / .115) ** 2)
    fitted[:, 1] += neckline_depth(index) * height * near_center * front * middle
    return fitted


def neckline_depth(index):
    return (-.014, -.036, .009)[index]


def scientist_neckline():
    source, texture = geometry.load("scientist")
    name, points, faces, uv = next(geometry.meshes(source))
    centers = points[faces].mean(axis=1)
    colors = geometry.sample(texture, uv.mean(axis=1)).astype(float)
    keep = keep_scientist(centers, geometry.skin_color(texture, uv), colors, name)
    return collar_ring(points, faces, keep)[:, 0]


def fit_trousers(points, index):
    x, y, z = points.T
    clothing = geometry.smoothstep((y - .105) / .057) * (1 - geometry.smoothstep((y - .400) / .060))
    center_front = np.exp(-(x / .127) ** 2) * geometry.smoothstep(z / .12)
    groin = np.exp(-((y - .296) / .095) ** 2)
    fitted = points.copy()
    fitted[:, 1] += (.052, .068, .044)[index] * center_front * groin * clothing
    depth_limit = np.where(z >= 0, .152, .169) + (.0, -.012, .011)[index]
    excess = np.maximum(abs(z) - depth_limit, 0)
    fitted[:, 2] -= np.sign(z) * (excess * .85 + .035 * center_front * groin) * clothing
    leg_center = .115 * np.sign(x)
    width = (1.01, .88, 1.13)[index]
    fitted[:, 0] += (x - leg_center) * (width - 1) * clothing
    return fitted


def edited_mesh(text, prim, world, fitted, faces, transform):
    indent = prim[1]
    start = text.index("\n" + indent + "{", prim.start()) + len(indent) + 2
    end = text.index("\n" + indent + "}", start)
    block = text[start:end]
    linear = transform[:3, :3]
    local = geometry.usd_array(block, "points", np.float64).reshape(-1, 3)
    local += (fitted - world) @ np.linalg.inv(linear)
    source_normals = geometry.usd_array(block, "normals", np.float64).reshape(-1, 3)
    old, _ = geometry.normals_for(world, faces)
    new, _ = geometry.normals_for(fitted, faces)
    delta = ((new - old) @ linear.T)[faces].reshape(-1, 3)
    normals = geometry.unit(source_normals + delta)
    changes = {"points": local, "normals": normals, "extent": [local.min(0), local.max(0)]}

    def replace(match):
        prefix, key, _, suffix = match.groups()
        return prefix[:-1] + geometry.float_array(changes[key]) + suffix[1:] if key in changes else match[0]

    return start, end, FACE_ARRAY.sub(replace, block)


def exposed_skin(costume, index, collar):
    _, points, faces, uv = next(part for part in geometry.seed_data if part[0] == "Body")
    if costume == "cat-bear":
        def mask(samples):
            x, y, z = samples.T
            height = (.799, .824, .868, .920, 1.075, 1.140, 1.171, 1.183)
            width = (.052, .080, .143, .191, .210, .175, .115, .042)
            return np.minimum.reduce((y - height[0], height[-1] - y,
                                      np.interp(y, height, width) - abs(x + .004), z - .069))
        return seal_hood_face(costume, *geometry.clipped_surface(points, faces, uv, mask))
    if costume == "scientist":
        def covered_edge(samples):
            x, y, z = samples.T
            _, phase, _ = collar_coords(samples)
            edge = np.interp(phase * .2 - .5, np.arange(72), collar, period=72)
            front = geometry.smoothstep((z - .06) / .08)
            edge += neckline_depth(index) * front * np.exp(-(x / .115) ** 2)
            return y - edge + .003
        return geometry.clipped_surface(points, faces, uv, covered_edge)
    return geometry.clipped_surface(points, faces, uv, lambda sample: sample[:, 1] - .54)


def generate_stage(costume, index, text, original, mesh_prims, skin):
    edits = []
    for prim, (name, points, faces, uv, transform) in zip(mesh_prims, original, strict=True):
        if name == "VisibleBody" and skin is not None:
            end = text.index("\n" + prim[1] + "}", prim.end()) + len(prim[1]) + 2
            replacement = geometry.as_mesh("VisibleBody", *skin).replace("/SeedCostume/Materials/mat0", SKIN_PATH)
            edits.append((prim.start(), end, replacement.rstrip()))
        elif name == "VisibleBody":
            x, y, z = points.T
            fitted = points.copy()
            if costume in PROFILE:
                center = geometry.smoothstep((aperture(costume, points) - .009) / .066)
                amount = .040 if costume == "astronaut" else .062
            else:
                radius = np.hypot((x + .004) / .177, (y - 1.05) / .215)
                center = 1 - geometry.smoothstep((radius - .30) / .65)
                amount = .019
            fitted[:, 2] -= amount * center * geometry.smoothstep((z - .083) / .068)
            edits.append(edited_mesh(text, prim, points, fitted, faces, transform))
        elif name.startswith(("mesh1", "InnerHood")):
            if costume == "scientist":
                fitted = fit_neckline(points, index)
            elif costume == "postech-selfie":
                fitted = fit_trousers(points, index)
            else:
                fitted = hood_fit(costume, points, index)
            edits.append(edited_mesh(text, prim, points, fitted, faces, transform))
    for start, end, block in reversed(edits):
        text = text[:start] + block + text[end:]
    if costume == "postech-selfie":
        master = geometry.read_stage(geometry.assets / "Characters/SeedCucumberMaster.usdz")
        material = overlay_material(master, "VisibleBodyMaterial", "Body")
        mesh = geometry.as_mesh("VisibleBody", *skin).replace("/SeedCostume/Materials/mat0", SKIN_PATH)
        marker = '    def Scope "Materials"\n    {\n'
        assert marker in text
        text = text.replace(marker, mesh + marker + material, 1)
    return text


def preview(costume, key, stage, maps, master):
    def pixels(data):
        return np.asarray(Image.open(io.BytesIO(data)).convert("RGB"))

    body = pixels(maps["Textures/BodyBaseColor.png"])
    cloth = pixels(next(value for key, value in maps.items() if key.startswith("textures/")))
    palette = {
        "VisorFrame": [168, 174, 157], "VisorStrap": [40, 44, 40],
        "LeftFrame": [45, 43, 39], "RightFrame": [45, 43, 39], "Bridge": [45, 43, 39],
        "LeftTemple": [45, 43, 39], "RightTemple": [45, 43, 39],
    }
    sections = []
    for name, points, faces, uv in geometry.meshes(stage):
        if name == "VisorLens":
            continue
        color = palette.get(name)
        bitmap = body if name == "VisibleBody" else cloth
        if color:
            bitmap = np.full((4, 4, 3), color, dtype=np.uint8)
        sections.append(([(name, points, faces, uv)], bitmap))
    for name, points, faces, uv in geometry.seed_data:
        if name not in ("LeftEye", "RightEye", "Mouth", "Stem"):
            continue
        if name == "Stem":
            points = points + STEMS.get(costume, (0, 0, 0))
        sections.append(([(name, points, faces, uv)], pixels(master.read(f"Textures/{name}.png"))))
    geometry.raster(None, sections, key)
    with Image.open(geometry.root / f"{key}-0.ppm") as frame:
        thumbnail = frame.crop((36, 14, 354, 532))
        thumbnail.thumbnail((150, 210))
        thumbnail.save(geometry.root.parent / key / f"{key}.jpg", quality=91)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workspace", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--costume", choices=COSTUMES, action="append")
    args = parser.parse_args()
    destination = args.output.resolve()
    resources = (args.workspace / "apps/ios/OiDonation/Resources").resolve()
    if destination.is_relative_to(resources):
        parser.error("output must be a staging directory")
    geometry.configure(resources, destination / "renders")
    if args.preview:
        subprocess.run(["/usr/bin/clang", "-O3", str(Path(__file__).with_name("raster.c")),
                        "-o", str(geometry.root / "raster")], check=True, timeout=30)
    master = ZipFile(resources / "Characters/SeedCucumberMaster.usdz")
    for costume in args.costume or COSTUMES:
        source = resources / "Characters" / f"seed-costume-{costume}.usdz"
        original = geometry.read_stage(source)
        parts = list(geometry.meshes(original, include_transform=True))
        prims = [prim for prim in geometry.prim_pattern.finditer(original) if prim[2] == "Mesh"]
        with ZipFile(source) as package:
            maps = {name: package.read(name) for name in package.namelist()[1:]}
        replace_skin = costume in ("cat-bear", "scientist", "postech-selfie")
        collar = scientist_neckline() if costume == "scientist" else None
        if replace_skin:
            for name in ("BodyBaseColor", "BodyNormal", "BodyRoughness"):
                entry = f"Textures/{name}.png"
                maps[entry] = master.read(entry)
        for i in range(3):
            skin = exposed_skin(costume, i, collar) if replace_skin else None
            key = f"seed-costume-{costume}-proposal-{i+1}"
            folder = destination / key
            folder.mkdir(exist_ok=True)
            stage = generate_stage(costume, i, original, parts, prims, skin)
            (folder / f"{key}.usda").write_text(stage)
            for name, data in maps.items():
                path = folder / name
                path.parent.mkdir(exist_ok=True, parents=True)
                path.write_bytes(data)
            for command in (("usdcat", "-o", f"{key}.usdc", f"{key}.usda"),
                            ("usdzip", f"{key}.usdz", f"{key}.usdc", *maps),
                            ("usdchecker", "--strict", "--arkit", f"{key}.usdz")):
                subprocess.run(("/usr/bin/" + command[0], *command[1:]), cwd=folder, check=True, timeout=35)
            if args.preview:
                preview(costume, key, stage, maps, master)
            print(key, flush=True)
    master.close()


if __name__ == "__main__":
    main()
