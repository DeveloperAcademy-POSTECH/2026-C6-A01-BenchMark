#!/usr/bin/env python3
"""Extract Pohang's dissolved city boundary from the official SGIS 2025 Q2 archive."""
import argparse
from collections import Counter
import json
from math import cos, degrees, radians, sin, sqrt, tan
from pathlib import Path
import struct
import zipfile

SEMI_MAJOR = 6378137.0
FLATTENING = 1 / 298.257222101
ECCENTRICITY_SQUARED = FLATTENING * (2 - FLATTENING)
SCALE = 0.9996
EASTING = 1000000.0
NORTHING = 2000000.0
CENTRAL_MERIDIAN = radians(127.5)
ORIGIN_LATITUDE = radians(38.0)


def meridional_arc(latitude):
    e = ECCENTRICITY_SQUARED
    return SEMI_MAJOR * (
        (1 - e / 4 - 3 * e**2 / 64 - 5 * e**3 / 256) * latitude
        - (3 * e / 8 + 3 * e**2 / 32 + 45 * e**3 / 1024) * sin(2 * latitude)
        + (15 * e**2 / 256 + 45 * e**3 / 1024) * sin(4 * latitude)
        - (35 * e**3 / 3072) * sin(6 * latitude)
    )


ORIGIN_ARC = meridional_arc(ORIGIN_LATITUDE)


def to_wgs84(easting, northing):
    """Inverse Transverse Mercator series, USGS PP 1395 §8. KGD2002 ≈ WGS84."""
    e = ECCENTRICITY_SQUARED
    ep = e / (1 - e)
    e1 = (1 - sqrt(1 - e)) / (1 + sqrt(1 - e))
    arc = ORIGIN_ARC + (northing - NORTHING) / SCALE
    mu = arc / (SEMI_MAJOR * (1 - e / 4 - 3 * e**2 / 64 - 5 * e**3 / 256))
    phi = (mu + (3 * e1 / 2 - 27 * e1**3 / 32) * sin(2 * mu)
           + (21 * e1**2 / 16 - 55 * e1**4 / 32) * sin(4 * mu)
           + (151 * e1**3 / 96) * sin(6 * mu) + (1097 * e1**4 / 512) * sin(8 * mu))
    c = ep * cos(phi)**2
    t = tan(phi)**2
    n = SEMI_MAJOR / sqrt(1 - e * sin(phi)**2)
    r = SEMI_MAJOR * (1 - e) / (1 - e * sin(phi)**2)**1.5
    d = (easting - EASTING) / (n * SCALE)
    latitude = phi - n * tan(phi) / r * (
        d**2 / 2 - (5 + 3 * t + 10 * c - 4 * c**2 - 9 * ep) * d**4 / 24
        + (61 + 90 * t + 298 * c + 45 * t**2 - 252 * ep - 3 * c**2) * d**6 / 720
    )
    longitude = CENTRAL_MERIDIAN + (
        d - (1 + 2 * t + c) * d**3 / 6
        + (5 - 2 * c + 28 * t - 3 * c**2 + 8 * ep + 24 * t**2) * d**5 / 120
    ) / cos(phi)
    return [round(degrees(longitude), 8), round(degrees(latitude), 8)]


def signed_area(ring):
    x, y = ring[0]
    return sum((a - x) * (d - y) - (c - x) * (b - y)
               for (a, b), (c, d) in zip(ring, ring[1:])) / 2


def source_rings(archive):
    with zipfile.ZipFile(archive) as source:
        entries = {Path(name).suffix[1:]: name for name in source.namelist()
                   if Path(name).stem == "bnd_sigungu_00_2025_2Q"}
        dbf, index, shapes = (source.read(entries[ext]) for ext in ("dbf", "shx", "shp"))
        projection = source.read(entries["prj"]).decode()
    if 'SPHEROID["GRS_1980",6378137.0,298.257222101]' not in projection:
        raise ValueError("Expected SGIS Unified Coordinate System (EPSG:5179)")
    record_count, header_length, record_length = struct.unpack_from("<IHH", dbf, 4)
    fields = [(dbf[start:start + 11].split(b"\0")[0], dbf[start + 16])
              for start in range(32, header_length - 1, 32)]
    if fields != [(b"BASE_DATE", 8), (b"SIGUNGU_CD", 5), (b"SIGUNGU_NM", 25)]:
        raise ValueError(f"Unexpected SGIS fields: {fields}")
    selected = {}
    districts = {"37011": "포항시 남구", "37012": "포항시 북구"}
    for i in range(record_count):
        start = header_length + i * record_length
        row = dbf[start:start + record_length]
        code = row[9:14].decode()
        if code not in districts:
            continue
        if row[0:9] != b" 20250630" or row[14:].decode().strip() != districts[code] or code in selected:
            raise ValueError(f"Unexpected SGIS record: {row!r}")
        offset = 2 * struct.unpack_from(">i", index, 100 + i * 8)[0]
        if struct.unpack_from("<i", shapes, offset + 8)[0] != 5:
            raise ValueError("Expected shapefile polygon")
        parts, points = struct.unpack_from("<ii", shapes, offset + 44)
        first = offset + 52
        stops = [*struct.unpack_from("<" + "i" * parts, shapes, first), points]
        start = first + 4 * parts
        coordinates = list(struct.iter_unpack("<dd", shapes[start:start + 16 * points]))
        selected[code] = [coordinates[a:b] for a, b in zip(stops, stops[1:])]
    if selected.keys() != districts.keys():
        raise ValueError("Expected both Pohang districts")
    return selected["37011"] + selected["37012"]


def dissolve(rings):
    # The official adjacent districts share their boundary segments exactly.
    # Opposite directed edges cancel, leaving only closed exterior rings.
    if any(ring[0] != ring[-1] or signed_area(ring) >= 0 for ring in rings):
        raise ValueError("Unexpected open ring or interior hole in these source records")
    edges = Counter((a, b) for ring in rings for a, b in zip(ring, ring[1:]) if a != b)
    if any(count != 1 for count in edges.values()):
        raise ValueError("Repeated oriented edge in source rings")
    retained = {(a, b) for a, b in edges if (b, a) not in edges}
    next_point = dict(retained)
    if (len(next_point) != len(retained) or set(next_point) != set(next_point.values())
            or len(retained) == len(edges)):
        raise ValueError("The source district edges do not form a shared closed boundary")
    merged = []
    while next_point:
        start = min(next_point)
        ring = [start]
        while True:
            ring.append(next_point.pop(ring[-1]))
            if ring[-1] == start:
                break
        if signed_area(ring) >= 0:
            raise ValueError("Unexpected merged polygon orientation")
        merged.append(ring)
    if abs(sum(map(signed_area, rings)) - sum(map(signed_area, merged))) > 0.1:
        raise ValueError("Dissolving the districts changed their combined area")
    return sorted(merged, key=signed_area)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    rings = dissolve(source_rings(args.archive))
    polygons = [[list(map(lambda point: to_wgs84(*point), reversed(ring)))] for ring in rings]
    points = [point for polygon in polygons for ring in polygon for point in ring]
    if not all(128.9 < lon < 129.7 and 35.8 < lat < 36.4 for lon, lat in points):
        raise ValueError("Transformed coordinates outside the Pohang region")
    lines = [json.dumps(polygon, separators=(",", ":")) for polygon in polygons]
    args.output.write_text('{"type":"MultiPolygon","coordinates":[\n' + ",\n".join(lines) + "\n]}\n")
    print(f"Pohang SGIS 2025 Q2: {len(polygons)} polygons, {len(points)} coordinates, {args.output.stat().st_size} bytes")


if __name__ == "__main__":
    main()
