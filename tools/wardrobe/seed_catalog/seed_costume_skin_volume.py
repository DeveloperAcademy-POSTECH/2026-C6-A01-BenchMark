"""Close trimmed skin behind the retained visible surface."""
import numpy as np


def seal_skin_cuts(points, faces, uv, inset):
    """Connect each open rim to a smaller interior ring and close its back."""
    if not len(faces):
        return points, faces, uv

    used, local = np.unique(faces, return_inverse=True)
    _, weld = np.unique(points[used].round(7), axis=0, return_inverse=True)
    welded_faces = weld[local].reshape(-1, 3)
    good = (welded_faces[:, 0] != welded_faces[:, 1]) & (welded_faces[:, 1] != welded_faces[:, 2])
    good &= welded_faces[:, 2] != welded_faces[:, 0]
    welded_faces = welded_faces[good]
    retained_faces = faces[good]
    retained_uv = uv[good]

    edge_corners = ((0, 1), (1, 2), (2, 0))
    directed = np.concatenate([welded_faces[:, pair] for pair in edge_corners])
    original = np.concatenate([retained_faces[:, pair] for pair in edge_corners])
    edge_uv = np.concatenate([retained_uv[:, pair] for pair in edge_corners])
    _, edge_ids, incidence = np.unique(np.sort(directed, axis=1), axis=0,
                                       return_inverse=True, return_counts=True)
    boundary = incidence[edge_ids.ravel()] == 1
    directed = directed[boundary]
    original = original[boundary]
    edge_uv = edge_uv[boundary]

    outgoing = {}
    incoming = {}
    for index, (start, end) in enumerate(directed):
        outgoing.setdefault(start, []).append(index)
        incoming.setdefault(end, []).append(index)
    if outgoing.keys() != incoming.keys() or any(
        len(edges) != 1 or len(incoming[start]) != 1 for start, edges in outgoing.items()
    ):
        raise ValueError("Trimmed skin boundary is not a set of oriented loops")

    extra_points, extra_faces, extra_uv = [], [], []
    next_index = len(points)
    while outgoing:
        start = current = next(iter(outgoing))
        loop = []
        while current in outgoing:
            edge = outgoing.pop(current)[0]
            loop.append(edge)
            current = directed[edge, 1]
        if current != start:
            raise ValueError("Trimmed skin boundary does not close")

        front = points[original[loop, 0]]
        inner = np.asarray(inset(front))
        if inner.shape != front.shape or not np.isfinite(inner).all():
            raise ValueError("Invalid inner skin rim")
        hub = next_index + len(loop)
        extra_points.extend(inner)
        extra_points.append(inner.mean(axis=0))
        for index, edge in enumerate(loop):
            a, b = original[edge]
            i = next_index + index
            j = next_index + (index + 1) % len(loop)
            extra_faces.extend(((b, a, i), (b, i, j), (j, i, hub)))
            uv_a, uv_b = edge_uv[edge]
            extra_uv.extend(((uv_b, uv_a, uv_a), (uv_b, uv_a, uv_b),
                             (uv_b, uv_a, (uv_a + uv_b) * .5)))
        next_index = hub + 1

    if not extra_faces:
        return points, retained_faces, retained_uv
    return (np.vstack((points, extra_points)), np.vstack((retained_faces, extra_faces)),
            np.concatenate((retained_uv, np.asarray(extra_uv))))
