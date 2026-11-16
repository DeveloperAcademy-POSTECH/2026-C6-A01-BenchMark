"""Bake an approved skin palette into the eight separated outfits.

Run with Blender 4.5: blender --background --python apply_cat_skin.py -- SOURCE OUTPUT
SOURCE contains the original eight USDZs and wardrobe-costume-cat.usdz. OUTPUT
must be separate. Only skin material bindings change; geometry and garment
materials are compared to the source before a package is accepted.
Use --palette fresh-cucumber for the approved third color option.
Use --palette fresh-cucumber-bright4 for the approved fourth brightness option.
"""
import argparse
import hashlib
import json
import shutil
import struct
import sys
import zipfile
from pathlib import Path

import bpy
import numpy as np
from pxr import Sdf, Usd, UsdGeom, UsdShade, UsdUtils

NAMES = [f"wardrobe-{top}-{bottom}" for top in
         ("tshirt", "hoodie", "cardigan", "postech") for bottom in ("shorts", "long")]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pixels(image):
    data = np.empty(len(image.pixels), np.float32)
    image.pixels.foreach_get(data)
    return data.reshape(-1, 4)[:, :3]


def linear(rgb):
    rgb = np.asarray(rgb, dtype=float)
    return np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)


def green_mask(rgb):
    return (rgb[:, 1] > rgb[:, 0] * 1.18) & (rgb[:, 1] > rgb[:, 2] * 1.5) & (rgb[:, 1] > .05)


def palette(rgb):
    green = rgb[green_mask(rgb)]
    return np.median(green[green[:, 1] < .5], axis=0), np.median(green[green[:, 1] > .6], axis=0)


def unpack(source, directory):
    directory.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source) as archive:
        assert archive.testzip() is None
        for name in archive.namelist():
            assert not Path(name).is_absolute() and '..' not in Path(name).parts
        archive.extractall(directory)
        return directory / archive.namelist()[0]


def bake_palette(source, destination, reference):
    """Bake the same linear-light color ramp used in the approved preview."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    image = bpy.data.images.load(str(source))
    dark, light = palette(pixels(image))
    new_dark, new_light = linear(reference['stripe']), linear(reference['base'])
    bpy.ops.mesh.primitive_plane_add(size=2)
    plane = bpy.context.object
    material = bpy.data.materials.new('Cat skin palette bake')
    material.use_nodes = True
    plane.data.materials.append(material)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    nodes.clear()
    texture = nodes.new('ShaderNodeTexImage')
    texture.image = image
    separate = nodes.new('ShaderNodeSeparateColor')
    separate.mode = 'RGB'
    links.new(texture.outputs['Color'], separate.inputs['Color'])
    ramp = nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.interpolation = 'LINEAR'
    ramp.color_ramp.elements.remove(ramp.color_ramp.elements[1])
    ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    for position, color in [(linear(dark)[1], new_dark), (linear(light)[1], new_light),
                            (1, np.minimum(new_light * 1.10, 1))]:
        element = ramp.color_ramp.elements.new(min(.99999, max(.00001, float(position))))
        element.color = (*color, 1)
    links.new(separate.outputs['Green'], ramp.inputs['Fac'])
    checks = []
    for channel, factor in [('Red', 1.18), ('Blue', 1.5)]:
        multiply = nodes.new('ShaderNodeMath')
        multiply.operation = 'MULTIPLY'
        multiply.inputs[1].default_value = factor
        links.new(separate.outputs[channel], multiply.inputs[0])
        check = nodes.new('ShaderNodeMath')
        check.operation = 'GREATER_THAN'
        links.new(separate.outputs['Green'], check.inputs[0])
        links.new(multiply.outputs[0], check.inputs[1])
        checks.append(check)
    mask = nodes.new('ShaderNodeMath')
    mask.operation = 'MULTIPLY'
    for index, check in enumerate(checks):
        links.new(check.outputs[0], mask.inputs[index])
    mix = nodes.new('ShaderNodeMixRGB')
    links.new(mask.outputs[0], mix.inputs[0])
    links.new(texture.outputs['Color'], mix.inputs[1])
    links.new(ramp.outputs['Color'], mix.inputs[2])
    emission = nodes.new('ShaderNodeEmission')
    links.new(mix.outputs[0], emission.inputs['Color'])
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(emission.outputs[0], output.inputs['Surface'])
    baked = bpy.data.images.new('Skin color', width=image.size[0], height=image.size[1], alpha=False)
    baked.colorspace_settings.name = 'sRGB'
    target = nodes.new('ShaderNodeTexImage')
    target.image = baked
    nodes.active = target
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 1
    scene.render.bake.margin = 0
    bpy.ops.object.bake(type='EMIT')
    baked.filepath_raw = str(destination)
    baked.file_format = 'PNG'
    baked.save()
    return {'sourceSHA256': sha(source), 'outputSHA256': sha(destination),
            'size': list(image.size), 'oldBaseRGB': np.rint(light * 255).astype(int).tolist(),
            'oldStripeRGB': np.rint(dark * 255).astype(int).tolist()}


def skin(prim):
    return any(part.startswith('Skin_') for part in str(prim.GetPath()).split('/'))


def shader(material):
    return next(UsdShade.Shader(prim) for prim in Usd.PrimRange(material.GetPrim())
                if prim.IsA(UsdShade.Shader) and UsdShade.Shader(prim).GetIdAttr().Get() == 'UsdPreviewSurface')


def texture_shader(stage, surface):
    connection = surface.GetInput('diffuseColor').GetAttr().GetConnections()
    assert len(connection) == 1
    return UsdShade.Shader(stage.GetPrimAtPath(connection[0].GetPrimPath()))


def validate(source, output, material_suffix='_CatSkin'):
    before, after = Usd.Stage.Open(str(source)), Usd.Stage.Open(str(output))
    mesh_count = skin_count = 0
    for original in before.Traverse():
        changed = after.GetPrimAtPath(original.GetPath())
        assert changed and original.GetTypeName() == changed.GetTypeName(), original.GetPath()
        # All original attributes (including geometry, UVs and original materials) stay identical.
        for attr in original.GetAttributes():
            actual = changed.GetAttribute(attr.GetName())
            expected, value = attr.Get(), actual.Get()
            if isinstance(expected, Sdf.AssetPath):
                assert expected.path == value.path
            else:
                assert expected == value, attr.GetPath()
            assert attr.GetConnections() == actual.GetConnections(), attr.GetPath()
            assert attr.GetAllMetadata() == actual.GetAllMetadata(), attr.GetPath()
        for relation in original.GetRelationships():
            if skin(original) and relation.GetName() == 'material:binding':
                continue
            assert relation.GetTargets() == changed.GetRelationship(relation.GetName()).GetTargets()
        if original.IsA(UsdGeom.Mesh):
            mesh_count += 1
            if skin(original):
                skin_count += 1
                mat = UsdShade.MaterialBindingAPI(changed).ComputeBoundMaterial()[0]
                assert str(mat.GetPath()).endswith(material_suffix)
                surface = shader(mat)
                assert abs(surface.GetInput('roughness').Get() - 155 / 255) < 1e-6
                assert not surface.GetInput('roughness').GetAttr().GetConnections()
                assert surface.GetInput('metallic').Get() == 0
                assert surface.GetInput('clearcoat').Get() == 0
                assert not surface.GetInput('metallic').GetAttr().GetConnections()
    assert skin_count in (3, 5)
    assert UsdGeom.GetStageUpAxis(after) == 'Y' and UsdGeom.GetStageMetersPerUnit(after) == 1
    bounds = UsdGeom.BBoxCache(Usd.TimeCode.Default(), ['default', 'render']).ComputeWorldBound(after.GetDefaultPrim()).ComputeAlignedRange()
    assert abs(bounds.GetSize()[1] - 1.5) < .005
    assert abs(bounds.GetMin()[1]) < .005
    with zipfile.ZipFile(source) as old, zipfile.ZipFile(output) as new:
        assert new.testzip() is None
        for name in old.namelist()[1:]:
            assert old.read(name) == new.read(name), name
        raw = output.read_bytes()
        for entry in new.infolist():
            assert entry.compress_type == zipfile.ZIP_STORED
            name_length, extra_length = struct.unpack_from('<HH', raw, entry.header_offset + 26)
            assert (entry.header_offset + 30 + name_length + extra_length) % 64 == 0
        for prim in after.Traverse():
            for attr in prim.GetAttributes():
                value = attr.Get()
                if isinstance(value, Sdf.AssetPath) and value.path:
                    assert value.path.removeprefix('./') in new.namelist(), value.path
    return {'meshes': mesh_count, 'skinMeshes': skin_count, 'heightMeters': bounds.GetSize()[1],
            'geometryUVsTransformsUnchanged': True, 'garmentMaterialsUnchanged': True,
            'originalTextureBytesUnchanged': True, 'selfContainedAlignedUSDZ': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--palette', choices=['cat', 'fresh-cucumber', 'fresh-cucumber-bright4'], default='cat')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    source, output = args.source.resolve(), args.output.resolve()
    assert source != output and source not in output.parents
    output.mkdir(parents=True, exist_ok=True)
    scratch = output / 'work'
    root = unpack(source / 'wardrobe-costume-cat.usdz', scratch / 'reference')
    bpy.ops.wm.read_factory_settings(use_empty=True)
    color = pixels(bpy.data.images.load(str(root.parent / 'textures/cat-1.png')))
    dark, light = palette(color)
    rough = pixels(bpy.data.images.load(str(root.parent / 'textures/cat-3.png')))
    # Approved looks were rendered from the original atlases, not from an
    # already recolored texture; this avoids accumulating color/edge changes.
    if args.palette == 'fresh-cucumber':
        light = np.array([126, 185, 80], dtype=float) / 255
        dark = np.array([43, 96, 49], dtype=float) / 255
    elif args.palette == 'fresh-cucumber-bright4':
        light = np.array([151, 211, 106], dtype=float) / 255
        dark = np.array([55, 108, 60], dtype=float) / 255
    material_suffix = {'cat': '_CatSkin', 'fresh-cucumber': '_FreshSkin',
                       'fresh-cucumber-bright4': '_BrightFreshSkin'}[args.palette]
    reference = {'base': light.tolist(), 'stripe': dark.tolist(),
                 'roughness': float(np.median(rough[green_mask(color), 0]))}
    assert abs(reference['roughness'] - 155 / 255) < 1e-6
    report = {'version': 3, 'palette': args.palette, 'reference': 'wardrobe-costume-cat.usdz',
              'referenceSHA256': sha(source / 'wardrobe-costume-cat.usdz'),
              'baseRGB': np.rint(light * 255).astype(int).tolist(),
              'stripeRGB': np.rint(dark * 255).astype(int).tolist(),
              'roughness': reference['roughness'], 'metallic': 0, 'clearcoat': 0,
              'textures': {}, 'models': []}
    cache = {}
    for name in NAMES:
        original = source / (name + '.usdz')
        root = unpack(original, scratch / name)
        stage = Usd.Stage.Open(str(root))
        layer = stage.GetRootLayer()
        materials = {}
        for prim in list(stage.Traverse()):
            if not prim.IsA(UsdGeom.Mesh) or not skin(prim):
                continue
            original_mat = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0]
            old_path = original_mat.GetPath()
            if old_path not in materials:
                new_path = old_path.GetParentPath().AppendChild(old_path.name + material_suffix)
                assert not stage.GetPrimAtPath(new_path), 'Use the original, unrecolored input assets'
                Sdf.CopySpec(layer, old_path, layer, new_path)
                new_mat = UsdShade.Material(stage.GetPrimAtPath(new_path))
                for node in Usd.PrimRange(new_mat.GetPrim()):
                    for attr in node.GetAttributes():
                        if attr.GetConnections():
                            attr.SetConnections([p.ReplacePrefix(old_path, new_path) for p in attr.GetConnections()])
                surface = shader(new_mat)
                tex = texture_shader(stage, surface)
                old_texture = root.parent / tex.GetInput('file').Get().path
                digest = sha(old_texture)
                new_name = f'textures/skin-{args.palette}-{digest[:12]}.png'
                new_texture = root.parent / new_name
                if digest in cache:
                    shutil.copy2(cache[digest], new_texture)
                else:
                    report['textures'][digest] = bake_palette(old_texture, new_texture, reference)
                    cache[digest] = new_texture
                tex.GetInput('file').Set(Sdf.AssetPath('./' + new_name))
                for parameter, value in [('roughness', reference['roughness']), ('metallic', 0), ('clearcoat', 0)]:
                    inp = surface.GetInput(parameter)
                    inp.GetAttr().SetConnections([])
                    inp.Set(value)
                materials[old_path] = new_mat
            UsdShade.MaterialBindingAPI(prim).Bind(materials[old_path])
        layer.Save()
        packaged = output / (name + '.usdz')
        assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(root)), str(packaged))
        checks = validate(original, packaged, material_suffix)
        report['models'].append({'file': packaged.name, 'sourceSHA256': sha(original),
                                  'outputSHA256': sha(packaged), 'bytes': packaged.stat().st_size, **checks})
        (output / 'skin-material-manifest.json').write_text(json.dumps(report, indent=2) + '\n')
        print('VERIFIED', name, checks, flush=True)


if __name__ == '__main__':
    main()
