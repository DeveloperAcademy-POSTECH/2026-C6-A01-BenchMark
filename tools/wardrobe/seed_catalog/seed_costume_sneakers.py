"""Fit the original open-collar sneakers to the neutral character's ankles."""
from pathlib import Path
import re
import subprocess

import numpy as np

import seed_costume_geometry as geometry
from seed_costume_geometry import clipped_surface, skin_part, smoothstep


def mesh_block(text, name):
    start = re.search(r'(?m)^( +)def Mesh "' + re.escape(name) + r'"(?: \(|\n)', text)
    if start is None:
        raise ValueError("Missing mesh " + name)
    end = text.index("\n" + start[1] + "}", start.end())
    return text[start.start():end+len(start[1])+2]


def read_array(content, name, dtype, columns):
    return geometry.usd_array(content, name, dtype).reshape(-1, columns)


def y_up(points):
    return np.column_stack([points[:, 0], points[:, 2], -points[:, 1]])


def replace_array(content, name, rows):
    result, count = re.subn(
        r'(?m)^(\s+\w+\[\] ' + re.escape(name) + r' = )\[[^\]]*\]',
        lambda match: match[1] + "[" + ", ".join(
            "(" + ", ".join(format(v, ".9g") for v in row) + ")" for row in rows
        ) + "]",
        content, count=1,
    )
    if count != 1:
        raise ValueError("Missing " + name)
    return result


def fit(points):
    # Keep the real shoe panels and the rounded toe. Scale about each original
    # ankle and let the green shins pass through the collar independently.
    fitted = points.copy()
    for side, target_x in [(-1, -.102), (1, .109)]:
        ids = np.sign(points[:, 0]) == side
        x, y, z = points[ids].T
        ankle_x, ankle_z = side * .1205, -.022
        yaw = np.deg2rad(-side * 3.0)
        x, z = x - ankle_x, z - ankle_z
        fitted[ids, 0] = target_x + .84 * (x * np.cos(yaw) + z * np.sin(yaw))
        fitted[ids, 1] = .87 * y + .001
        fitted[ids, 2] = .007 + .77 * (-x * np.sin(yaw) + z * np.cos(yaw))
    return fitted


def package_content(stage, points, faces, output):
    start = mesh_block(stage, "shorts_shoes_001")
    orig_normal = y_up(read_array(start, "normals", np.float64, 3))
    # Transport authored split normals through the fit to preserve stitch and sole breaks.
    eps = 0.000025
    jacobian = np.stack([(fit(points + axis * eps) - fit(points - axis * eps)) / (2 * eps)
                         for axis in np.eye(3)], axis=-1)
    transport = np.linalg.inv(jacobian).transpose(0, 2, 1)
    normals = np.einsum("nij,nj->ni", transport[faces.flatten()], orig_normal)
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    fitted = fit(points)
    section = start.replace('"shorts_shoes_001"', '"Shoes"').replace('/OiWardrobe/_materials/', '/SeedCucumberSneakers/Materials/')
    section = section.replace("prepend apiSchemas =", "apiSchemas =")
    section = re.sub(r'^\s*float\[\] primvars:PreserveSeams = \[[^\]]*\] \(\n[^\n]+\n\s*\)\n', '\n', section, flags=re.M)
    section = replace_array(section, "extent", [fitted.min(0), fitted.max(0)])
    section = replace_array(section, "points", fitted)
    section = replace_array(section, "normals", normals)
    material = re.search(r'(?ms)^        def Material "WhiteSneakers"\n.*?^        }', stage)[0]
    material = material.replace('/OiWardrobe/_materials/', '/SeedCucumberSneakers/Materials/')
    shins = []
    for name, leg, leg_faces, uv in geometry.seed_data:
        if name not in ("LeftLeg", "RightLeg"):
            continue
        # The factory legs merge with rounded bare feet well below the opening.
        # Only the invisible lower section is removed from the shoe outfit copy.
        leg, leg_faces, uv = clipped_surface(leg, leg_faces, uv, lambda p: p[:, 1] - .079)
        leg = leg.copy()
        cuff = 1 - smoothstep((leg[:, 1] - .079) / .039)
        ankle = np.array([-.102 if name == "LeftLeg" else .109, .007])
        leg[:, [0, 2]] = ankle + (leg[:, [0, 2]] - ankle) * (1 - .37 * cuff[:, None])
        shin, shin_material = skin_part(name, f"Shin{name}", f"{name}Skin", leg, leg_faces, uv, output,
                                       prim="SeedCucumberSneakers")
        shins.append(shin)
        material += "\n" + shin_material
    extra = "\n".join(shins)
    return f"""#usda 1.0
(
    defaultPrim = "SeedCucumberSneakers"
    metersPerUnit = 1
    upAxis = "Y"
)
def Xform "SeedCucumberSneakers"
{{
{section}
{extra}
    def Scope "Materials"
    {{
{material}
    }}
}}
"""


def prepare(output):
    """Write SeedCucumberSneakers.usdz from the existing shorts outfit and neutral fit."""
    source = geometry.assets / "Wardrobe" / "wardrobe-tshirt-shorts.usdz"
    stage = geometry.read_stage(source)
    sneaker = mesh_block(stage, "shorts_shoes_001")
    points = y_up(read_array(sneaker, "points", np.float64, 3))
    faces = read_array(sneaker, "faceVertexIndices", np.int64, 3)
    output.mkdir(parents=True, exist_ok=True)
    name = "SeedCucumberSneakers"
    stage_file = output / f"{name}.usda"
    stage_file.write_text(package_content(stage, points, faces, output))
    textures = sorted(str(path.relative_to(output)) for path in (output / "textures").glob("*.png"))
    for command in (
        ["/usr/bin/usdcat", "-o", f"{name}.usdc", f"{name}.usda"],
        ["/usr/bin/usdzip", f"{name}.usdz", f"{name}.usdc", *textures],
        ["/usr/bin/usdchecker", "--strict", "--arkit", f"{name}.usdz"],
    ):
        subprocess.run(command, check=True, cwd=output, timeout=25)
