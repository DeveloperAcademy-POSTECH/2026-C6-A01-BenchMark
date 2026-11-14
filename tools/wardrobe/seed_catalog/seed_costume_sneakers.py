"""Fit the original open-collar sneakers to the neutral character's ankles."""
from pathlib import Path
import re
import subprocess

import numpy as np

import seed_costume_geometry as geometry
from seed_costume_geometry import smoothstep

FIT = (.78, .005, .80, .76, .47, .019, .046)


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


def fit(points, height, collar, width, depth, girth=0.0, heel_shift=0.0, inner=0.0):
    fitted = points.copy()
    for side, target_x in [(-1, -.102), (1, .109)]:
        ids = np.sign(points[:, 0]) == side
        x, y, z = points[ids].T
        anchor_x, anchor_z = side * .1205, -.022
        is_heel = (1 - smoothstep((z - .028) / .044))
        is_upper = smoothstep((y - .058) / .038)
        ease = is_heel * is_upper
        rear = (1 - smoothstep((z - .045) / .047))
        wall = rear * (1 - smoothstep((y - .077) / .027))
        fitted[ids, 0] = target_x + (x - anchor_x) * (width + (.25 * ease) + girth * wall) + side * heel_shift * wall
        inner_wall = (1 - smoothstep(((x - anchor_x) * side + .025) / .043))
        inner_wall *= smoothstep((y - .012) / .016) * (1 - smoothstep((y - .076) / .016))
        inner_wall *= smoothstep((z + .074) / .036) * (1 - smoothstep((z - .062) / .068))
        fitted[ids, 0] -= side * inner * inner_wall
        fitted[ids, 1] = y * height + ease * collar + .001
        fitted[ids, 2] = .006 + (z - anchor_z) * (depth + (.11 * ease))
    return fitted


def package_content(stage, points, faces, factors):
    start = mesh_block(stage, "shorts_shoes_001")
    orig_normal = y_up(read_array(start, "normals", np.float64, 3))
    # Transport authored split normals through the fit to preserve stitch and sole breaks.
    eps = 0.000025
    jacobian = np.stack([(fit(points + axis * eps, *factors) - fit(points - axis * eps, *factors)) / (2 * eps)
                         for axis in np.eye(3)], axis=-1)
    transport = np.linalg.inv(jacobian).transpose(0, 2, 1)
    normals = np.einsum("nij,nj->ni", transport[faces.flatten()], orig_normal)
    normals /= np.linalg.norm(normals, axis=1)[:, None]
    fitted = fit(points, *factors)
    section = start.replace('"shorts_shoes_001"', '"Shoes"').replace('/OiWardrobe/', '/SeedCucumberSneakers/')
    section = section.replace("prepend apiSchemas =", "apiSchemas =")
    section = re.sub(r'^\s*float\[\] primvars:PreserveSeams = \[[^\]]*\] \(\n[^\n]+\n\s*\)\n', '\n', section, flags=re.M)
    section = replace_array(section, "extent", [fitted.min(0), fitted.max(0)])
    section = replace_array(section, "points", fitted)
    section = replace_array(section, "normals", normals)
    material = re.search(r'(?ms)^        def Material "WhiteSneakers"\n.*?^        }', stage)[0]
    material = material.replace('/OiWardrobe/', '/SeedCucumberSneakers/')
    return f"""#usda 1.0
(
    defaultPrim = "SeedCucumberSneakers"
    metersPerUnit = 1
    upAxis = "Y"
)
def Xform "SeedCucumberSneakers"
{{
{section}
    def Scope "_materials"
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
    stage_file.write_text(package_content(stage, points, faces, FIT))
    for command in (
        ["/usr/bin/usdcat", "-o", f"{name}.usdc", f"{name}.usda"],
        ["/usr/bin/usdzip", f"{name}.usdz", f"{name}.usdc"],
        ["/usr/bin/usdchecker", "--strict", "--arkit", f"{name}.usdz"],
    ):
        subprocess.run(command, check=True, cwd=output, timeout=25)
