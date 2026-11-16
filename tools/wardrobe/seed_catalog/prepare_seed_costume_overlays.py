"""Package fitted costume-only overlays from the shipped wardrobe.

Requires NumPy, Pillow and the macOS USD command-line tools.
Example:
    python3 tools/wardrobe/seed_catalog/prepare_seed_costume_overlays.py . /tmp/seed-costumes astronaut bee
"""
from argparse import ArgumentParser
from pathlib import Path

import seed_costume_geometry as geometry
import seed_costume_school_science as school_science
import seed_costume_modular_tops as modular
import seed_costume_sneakers as sneakers
from seed_costume_bee import prepare_bee
from seed_costume_rigid_hoods import ORIGINAL_VOLUME_HOODS, prepare_rigid_hood
from seed_costume_soft_hoods import SOFT_HOODS, prepare_soft_hood
from seed_costume_coverage import add_scientist_body
from seed_costume_extras import add_ribbon_calves, prepare_selfie
from seed_costume_sports import SPORT_COSTUMES, recipe as sport_recipe

HOODED = ("bee", *SOFT_HOODS, *ORIGINAL_VOLUME_HOODS)
COSTUMES = (*HOODED, "school-uniform", *school_science.VARIANTS,
            *SPORT_COSTUMES, "postech-selfie")

def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("workspace", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("ids", nargs="*")
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    items = (*COSTUMES, "sneakers", *modular.SOURCES)
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
        if id in modular.SOURCES:
            modular.make_stage(work / id, resources, preview=args.preview, kind=id)
            continue
        if id == "sneakers":
            sneakers.prepare(work / id)
            continue
        if id in school_science.VARIANTS:
            needs_body_cut = id == "scientist"
            school_science.prepare(id, work / id, preview=args.preview and not needs_body_cut)
            if needs_body_cut:
                add_scientist_body(work / id)
                if args.preview:
                    _, _, hidden = school_science.VARIANTS[id]
                    school_science.review(id, work / id, {*hidden, "Body", "LeftLeg", "RightLeg"})
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
        if id == "bee":
            prepare_bee(work / id, preview=args.preview)
            continue
        if id in SOFT_HOODS:
            prepare_soft_hood(id, work / id, preview=args.preview)
            continue
        if id in ORIGINAL_VOLUME_HOODS:
            prepare_rigid_hood(id, work / id, preview=args.preview)
            continue

if __name__ == "__main__":
    main()
