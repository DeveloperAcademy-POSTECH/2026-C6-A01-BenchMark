#!/usr/bin/env python3
"""Conservative local check; App Store app-thinned variant report is authoritative."""
from pathlib import Path
import sys
bundle = Path(sys.argv[1])
assert bundle.is_dir(), f'Missing app bundle: {bundle}'
files = [p for p in bundle.rglob('*') if p.is_file()]
for path in files:
    assert path.suffix.lower() not in {'.usdz', '.reality', '.scn', '.fbx', '.glb'}, f'Bundled AR asset: {path}'
size = sum(p.stat().st_size for p in files)
assert size < 15_000_000, f'App Clip bundle too large: {size} bytes'
print(f'PASS: App Clip bundle {size:,} bytes ({size/1_000_000:.2f} MB), no bundled 3D assets')
print('Not an App Store thinning/codesigning report; repeat after signed Archive/export.')
