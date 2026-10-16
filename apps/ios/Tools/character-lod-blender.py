"""Run in a separate factory-startup Blender. Writes geometry-only USD overrides.
Materials, original scene transforms and textures are retained by the USD pipeline.
"""
import bpy, json, sys
from pathlib import Path

spec = json.loads(Path(sys.argv[sys.argv.index('--') + 1]).read_text())
for item in spec:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=item['source'])
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    assert len(meshes) == 1, 'Only single-mesh static assets are supported'
    obj = meshes[0]
    assert not obj.data.shape_keys and not obj.modifiers and not obj.animation_data
    original = sum(len(p.vertices)-2 for p in obj.data.polygons)
    modifier = obj.modifiers.new('MobileLOD', 'DECIMATE')
    modifier.ratio = min(1.0, item['triangles'] / original)
    modifier.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    mesh = obj.data
    assert all(len(p.vertices) == 3 for p in mesh.polygons)
    assert mesh.uv_layers.active is not None
    # USD importer retains local points; transforms and units live on parent Xforms.
    # These single-mesh source assets all use /Root/mesh1.
    with Path(item['overlay']).open('w') as f:
        f.write(item['metadata'])
        f.write('\nover "Root" {\n over "mesh1" {\n')
        def array(type_name, name, values, tuple_value=False, metadata=''):
            f.write(f'  {type_name}[] {name} = [')
            first=True
            for value in values:
                if not first: f.write(',')
                first=False
                f.write('('+','.join(format(x,'.9g') for x in value)+')' if tuple_value else str(value))
            f.write(']'+metadata+'\n')
        # Split only where normal/UV discontinuities require it, then store
        # vertex-interpolated arrays instead of repeating vectors per triangle.
        indices=[]; vertices=[]; normals=[]; uvs=[]; vertex_for={}
        for face in mesh.polygons:
            for loop_index in face.loop_indices:
                vertex_id=mesh.loops[loop_index].vertex_index
                normal=tuple(mesh.corner_normals[loop_index].vector)
                uv=tuple(mesh.uv_layers.active.data[loop_index].uv)
                key=(vertex_id, normal, uv)
                index=vertex_for.get(key)
                if index is None:
                    index=len(vertices);vertex_for[key]=index
                    vertices.append(tuple(mesh.vertices[vertex_id].co))
                    normals.append(normal);uvs.append(uv)
                indices.append(index)
        array('point3f','points',vertices,True)
        array('int','faceVertexCounts',(3 for p in mesh.polygons))
        array('int','faceVertexIndices',indices)
        array('normal3f','normals',normals,True,' (interpolation = "vertex")')
        array('texCoord2f','primvars:st',uvs,True,' (interpolation = "vertex")')
        f.write('  float3[] primvars:tangents = None\n }\n}\n')
    result = dict(name=Path(item['source']).stem, originalTriangles=original,
                  optimizedTriangles=len(mesh.polygons), vertices=len(mesh.vertices))
    Path(item['stats']).write_text(json.dumps(result))
    print('LODRESULT '+json.dumps(result),flush=True)
