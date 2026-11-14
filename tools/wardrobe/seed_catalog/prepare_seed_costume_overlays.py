"""Package fitted costume-only overlays from the shipped wardrobe.

Requires NumPy, Pillow and the macOS USD command-line tools.
Example:
    python3 tools/wardrobe/seed_catalog/prepare_seed_costume_overlays.py . /tmp/seed-costumes astronaut bee
"""
from argparse import ArgumentParser
from pathlib import Path

import seed_costume_geometry as geometry
import seed_costume_school_science as school_science
import seed_costume_sneakers as sneakers
from seed_costume_extras import add_ribbon_calves, prepare_selfie
from seed_costume_hoods import colors, options
from seed_costume_sports import SPORT_COSTUMES, recipe as sport_recipe

HOODED = ("astronaut", "astronaut-navy", "bee", "cat", "cat-bear", "dinosaur", "raincoat")
COSTUMES = (*HOODED, "school-uniform", *school_science.VARIANTS,
            *SPORT_COSTUMES, "postech-selfie")

def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("workspace", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("ids", nargs="*")
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    items = (*COSTUMES, "sneakers")
    selected = args.ids or items
    unknown = set(selected) - set(items)
    if unknown:
        parser.error(f"unknown costumes: {', '.join(sorted(unknown))}")
    work = args.output.resolve()
    resources = args.workspace / "apps/ios/OiDonation/Resources"
    if work.is_relative_to(resources.resolve()):
        parser.error("output must be a staging directory outside app resources")
    geometry.configure(resources, work / ".review")
    if args.preview:
        import subprocess
        subprocess.run(["/usr/bin/clang", "-O3", str(Path(__file__).with_name("raster.c")),
                        "-o", str(geometry.root / "raster")], check=True, timeout=30)
    for id in selected:
        if id == "sneakers":
            sneakers.prepare(work / id)
            continue
        if id in school_science.VARIANTS:
            school_science.prepare(id, work / id, preview=args.preview)
            continue
        if id in SPORT_COSTUMES:
            mask, fit, hidden, cleaner = sport_recipe(id)
            geometry.prepare(id, work / id, mask, fit, hidden=hidden, render=args.preview, clean_color=cleaner)
            continue
        if id == "school-uniform":
            geometry.prepare(id, work / id, geometry.ribbon_school, geometry.school_fit, render=False)
            add_ribbon_calves(work / id, args.preview)
            continue
        if id == "postech-selfie":
            prepare_selfie(work / id, args.preview)
            continue
        mask, fit, hidden = options(id)
        cleaner = (lambda texture: geometry.replace_baked_green(texture, colors[id])) if id in colors else None
        geometry.prepare(id, work / id, mask, fit, hidden=hidden, render=args.preview, clean_color=cleaner)

if __name__ == "__main__":
    main()
