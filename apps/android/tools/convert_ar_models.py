"""Run with Blender 4.5.1 --background --python this.py -- SOURCE_DIR OUTPUT_DIR.

Imports the user-provided ARTest USDZ files, preserves skeleton animation,
and exports embedded glTF 2.0. Static dense meshes are reduced for mobile GPUs.
"""
import bpy
import hashlib
import json
import pathlib
import sys

source, destination = map(pathlib.Path, sys.argv[sys.argv.index('--') + 1:])
destination.mkdir(parents=True, exist_ok=True)
report = []
for name in ('neopjuk', 'ponix', 'ponixVsNeopjuk', 'doni', 'neopjukAnimated'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    path = source / (name + '.usdz')
    bpy.ops.wm.usd_import(filepath=str(path), import_cameras=False, import_lights=False)
    scene = bpy.context.scene
    original_triangles = 0
    for obj in scene.objects:
        if obj.type != 'MESH':
            continue
        triangles = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        original_triangles += triangles
        # Preserve the full topology and weights of skinned/animated meshes.
        if not obj.find_armature() and triangles > 80000:
            modifier = obj.modifiers.new('MobileReduction', 'DECIMATE')
            modifier.ratio = 80000 / triangles
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    for image in bpy.data.images:
        if image.size[0] > 2048 or image.size[1] > 2048:
            ratio = 2048 / max(image.size)
            image.scale(max(1, round(image.size[0] * ratio)), max(1, round(image.size[1] * ratio)))
    output = destination / (name + '.glb')
    bpy.ops.export_scene.gltf(filepath=str(output), export_format='GLB',
        export_animations=True, export_animation_mode='ACTIONS',
        export_frame_range=False, export_force_sampling=True,
        export_skins=True, export_morph=True, export_yup=True)
    report.append({'name': name, 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
        'glb_sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
        'bytes': output.stat().st_size, 'original_triangles': original_triangles})
(destination / 'conversion.json').write_text(json.dumps(report, indent=2) + '\n')
