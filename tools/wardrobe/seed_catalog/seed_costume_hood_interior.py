"""Opaque skin and lining behind the soft costume opening."""

import numpy as np

import seed_costume_geometry as geometry
from seed_costume_skin_volume import seal_skin_cuts

# The back of each face occupies the cavity behind the unchanged visible rind.
CAVITY_HEIGHTS = {'bee': 1.005, 'cat': 1.033, 'cat-bear': 1.020, 'raincoat': 1.050}


def seal_hood_face(id, points, faces, uv):
    center_y = CAVITY_HEIGHTS[id]

    def inset(rim):
        inner = rim.copy()
        inner[:, 0] *= .96
        inner[:, 1] = center_y + .96 * (rim[:, 1] - center_y)
        inner[:, 2] = np.minimum(.038, rim[:, 2] - .024)
        return inner

    return seal_skin_cuts(points, faces, uv, inset)


def hood_inside(id, costume):
    """Give the existing hood inner faces their own opaque, inward-facing surface."""
    bottom = .737 if id == 'bee' else .790
    lining = []
    for name, points, faces, uv in costume:
        x, y, z = points[faces].mean(axis=1).T
        selected = (y > bottom) & (y < 1.33) & (abs(x) < .31) & (z < .18)
        if not np.any(selected):
            continue
        normals, _ = geometry.normals_for(points, faces)
        inner = points - .00065 * normals
        lining.append(('InnerHood' + name, inner, faces[selected, ::-1], uv[selected, ::-1]))
    return lining


def cut_costume(id, keep_cloth):
    """The hood belongs to the kept costume, excluding its legacy cucumber."""
    source, texture = geometry.load(id)
    for name, points, faces, uv in geometry.meshes(source):
        centers = points[faces].mean(axis=1)
        rgb = geometry.sample(texture, uv.mean(axis=1)).astype(float)
        keep = keep_cloth(centers, geometry.skin_color(texture, uv), rgb, name)
        yield name, points, faces[keep], uv[keep]


def raincoat_crown_inside():
    """Cover the old stem perforation from below the original hood crown."""
    count = 40
    angle = np.linspace(0, 2 * np.pi, count, endpoint=False)
    rim = np.column_stack((-.003 + .068 * np.cos(angle), np.full(count, 1.310),
                          .043 + .066 * np.sin(angle)))
    points = np.vstack((rim, (-.003, 1.315, .043), (-.003, 1.307, .043)))
    i = np.arange(count)
    j = np.roll(i, -1)
    upper = np.column_stack((np.full(count, count), j, i))
    lower = np.column_stack((np.full(count, count + 1), i, j))
    faces = np.vstack((upper, lower))
    uv = np.broadcast_to((.694122, .343956), (len(faces), 3, 2))
    return 'InnerCrown', points, faces, uv
