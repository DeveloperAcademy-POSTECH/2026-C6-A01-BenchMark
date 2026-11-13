"""Author costume-specific pieces for the ribbon uniform and POSTECH selfie outfit."""
import re
import subprocess
from zipfile import ZipFile

import numpy as np

import seed_costume_geometry as geometry
from seed_costume_geometry import as_mesh, smoothstep

SELFIE_PARTS = ("LeftArm", "RightArm", "LeftLeg", "RightLeg")
CALF_PARTS = ("LeftLeg", "RightLeg")


def selfie_mask(centers, green, _rgb, _name):
    x, y, z = centers.T
    lowered_hand = (x < -.237) & (y > .440) & (y < .590)
    clothes = (y < .912) & (~green | lowered_hand)
    phone = (x > .175) & (y > .84) & (y < 1.17) & (z > .10)
    posed_hand = (x > .235) & (y > .841) & (y < 1.045) & (z > .088)
    return clothes | phone | posed_hand


def selfie_fit(points, _faces, _name):
    x, y, z = points.T.copy()
    clothes = 1 - smoothstep((y - .81) / .14)
    points[:, 0] = x * (1 + .075 * clothes)
    points[:, 2] = z * (1 + .10 * clothes) + .012 * clothes
    body_points = (y > .37) & (y < .95) & (np.abs(x) < .245)
    clear = points[body_points].copy()
    geometry.body.push_out(clear, .012)
    points[body_points] = clear
    head = smoothstep((y - .92) / .12)
    points[:, 0] += .02 * x * head
    points[:, 2] += .028 * head
    crotch = (1 - smoothstep((np.abs(x) - .051) / .098))
    crotch *= smoothstep((y - .13) / .24) * (1 - smoothstep((y - .375) / .147))
    points[:, 1] -= .145 * crotch
    seat = (1 - smoothstep((np.abs(x) - .09) / .12))
    seat *= smoothstep((y - .24) / .15) * (1 - smoothstep((y - .43) / .085))
    points[:, 2] += (.055 * np.tanh(z / .035)) * seat
    patch = np.exp(-((y - .37) / .045) ** 2 - ((x - .12) / .083) ** 2)
    points[:, 2] += .025 * patch * smoothstep((z - .04) / .08)
    # Lowering the inseam changes the body section that the seat must clear.
    seat_band = (y < .46) & (points[:, 1] > .282) & (np.abs(x) < .216)
    clear = points[seat_band].copy()
    geometry.body.push_out(clear, .012)
    points[seat_band] = clear
    return points


def selfie_glasses():
    """Rebuild the thin frames whose original texture contained the old eyes."""
    angle = np.linspace(0, 2 * np.pi, 64, endpoint=False)
    rings = []
    temples = []
    for side in (-1, 1):
        x = .084 * side + .063 * np.cos(angle)
        y = 1.095 + .054 * np.sin(angle) - side * .015
        z = .227 - .70 * x ** 2
        rings.append(np.column_stack((x, y, z)))
        t = np.linspace(0, 1, 20)
        temples.append(np.column_stack((side * (.147 + .080 * t), 1.095 - side * .015 - .010 * t,
                                        .212 - .158 * t)))
    bridge_x = np.linspace(-.022, .022, 14)
    bridge = np.column_stack((bridge_x, 1.105 + .005 * np.sin(np.linspace(0, np.pi, 14)),
                              .227 - .70 * bridge_x ** 2))
    parts = []
    for name, curve, closed in (
        ("LeftFrame", rings[0], True), ("RightFrame", rings[1], True), ("Bridge", bridge, False),
        ("LeftTemple", temples[0], False), ("RightTemple", temples[1], False),
    ):
        tangent = (np.roll(curve, -1, axis=0) - np.roll(curve, 1, axis=0)) if closed else np.gradient(curve, axis=0)
        normal = geometry.unit(np.cross(tangent, np.tile([0., 0., 1.], (len(tangent), 1))))
        binormal = geometry.unit(np.cross(tangent, normal))
        vertices = []
        section = np.linspace(0, 2 * np.pi, 8, endpoint=False)
        for i, point in enumerate(curve):
            vertices.extend(point + .0046 * (np.cos(section)[:, None] * normal[i]
                            + np.sin(section)[:, None] * binormal[i]))
        faces = []
        for i in range(len(curve) if closed else len(curve) - 1):
            for j in range(8):
                a = 8 * i + j
                b = 8 * i + (j + 1) % 8
                c = 8 * ((i + 1) % len(curve)) + j
                d = 8 * ((i + 1) % len(curve)) + (j + 1) % 8
                faces.extend(((a, b, c), (b, d, c)))
        parts.append((name, np.asarray(vertices), np.asarray(faces), np.zeros((len(faces), 3, 2))))
    return parts


def prepare_selfie(output, preview=False):
    from seed_costume_school_science import material_surface

    name = "seed-costume-postech-selfie"
    geometry.prepare("postech-selfie", output, selfie_mask, selfie_fit, hidden=SELFIE_PARTS, render=False)
    file = output / f"{name}.usda"
    stage = file.read_text()
    marker = '    def Scope "Materials"\n    {\n'
    parts = selfie_glasses()
    frames = "".join(as_mesh(*part).replace("/mat0>", "/SelfieFrames>") for part in parts)
    material = material_surface("SelfieFrames", "(0.04, 0.035, 0.029)", .48)
    file.write_text(stage.replace(marker, frames + marker + material, 1))
    package_stage(output, name, [entry.removeprefix("./") for entry in geometry.archive.findall(stage)])
    if preview:
        preview_with_seed("postech-selfie", stage, SELFIE_PARTS, [
            (parts, np.full((4, 4, 3), (45, 43, 39), dtype=np.uint8)),
        ])


def add_ribbon_calves(output, preview):
    """Include the original visible calves while the loafers cover the feet."""
    name = "seed-costume-school-uniform"
    stage_file = output / f"{name}.usda"
    stage = stage_file.read_text()
    master_file = geometry.assets / "Characters" / "SeedCucumberMaster.usdz"
    master = geometry.read_stage(master_file)
    material_scope = '    def Scope "Materials"\n    {\n'
    textures = [entry.removeprefix("./") for entry in geometry.archive.findall(stage)]
    calves, limbs, materials = [], [], []
    for part, vertices, faces, uv in geometry.seed_data:
        if part not in CALF_PARTS:
            continue
        keep = vertices[faces][:, :, 1].mean(axis=1) > .076
        calf = ("Visible" + part, vertices, faces[keep], uv[keep])
        calves.append(calf)
        limbs.append(as_mesh(*calf).replace("/mat0>", f"/{part}>"))
        material = re.search(rf'(?ms)^        def Material "{part}"\n.*?^        \}}', master)[0]
        material = material.replace("/Cucumber/Materials/", "/SeedCostume/Materials/")
        material = re.sub(r"@(?:[^@]*\[)?(?:\./)?Textures/" + part + r"\.png(?:\])?@",
                          f"@Textures/{part}.png@", material)
        materials.append(material + "\n")
    stage_file.write_text(stage.replace(material_scope, "".join(limbs) + material_scope + "".join(materials), 1))
    with ZipFile(master_file) as source:
        for part in CALF_PARTS:
            entry = f"Textures/{part}.png"
            destination = output / entry
            destination.parent.mkdir(exist_ok=True)
            destination.write_bytes(source.read(entry))
            textures.append(entry)
    package_stage(output, name, textures)
    if preview:
        preview_with_seed("school-uniform", stage, CALF_PARTS, [], calves)


def package_stage(output, name, textures):
    (output / f"{name}.usdz").unlink()
    for command in (
        ["/usr/bin/usdcat", "-o", f"{name}.usdc", f"{name}.usda"],
        ["/usr/bin/usdzip", f"{name}.usdz", f"{name}.usdc", *textures],
        ["/usr/bin/usdchecker", "--strict", "--arkit", f"{name}.usdz"],
    ):
        subprocess.run(command, cwd=output, check=True, timeout=25)


def preview_with_seed(id, stage, hidden, accessories, extra_skin=()):
    from PIL import Image

    _, texture = geometry.load(id)
    packages = [(list(geometry.meshes(stage)), texture), *accessories]
    master_file = geometry.assets / "Characters" / "SeedCucumberMaster.usdz"
    with ZipFile(master_file) as source:
        for part in [*geometry.seed_data, *extra_skin]:
            if part[0] in hidden:
                continue
            suffix = part[0].removeprefix("Visible")
            if suffix == "Body":
                suffix = "BodyBaseColor"
            with source.open(f"Textures/{suffix}.png") as file:
                packages.append(([part], np.asarray(Image.open(file).convert("RGB"))))
    geometry.raster(None, packages, id + "-overlay")
