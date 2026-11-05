"""Optimize complete (non-modular) USDZ costumes; source files remain untouched.
Blender -b --python tools/wardrobe/prepare_mobile_costumes.py -- WORKSPACE OUTPUT REPORT [ID ...]
OUTPUT is a staging directory. Review its renders before copying models/thumbnails into the app.
"""
import hashlib, json, math, subprocess, sys, tempfile, zipfile
from pathlib import Path
import bpy, bmesh
from mathutils import Vector
from pxr import Usd, UsdGeom, UsdUtils, Sdf

args = sys.argv[sys.argv.index('--') + 1:]
work, out, report = map(lambda p: Path(p).resolve(), args[:3])
selected = args[3:]
# Existing persisted IDs stay stable. The source library is not included in the app bundle.
SOURCES = {
 'baseball': 'baseball', 'farmer': 'farmer', 'martial-arts': 'martial-arts',
 'sportswear': 'sportswear', 'cowboy': 'cowboy', 'school-uniform': 'school-uniform',
 'school-uniform-trousers': 'school-uniform-trousers', 'astronaut-navy': 'astronaut-navy',
 'scientist-goggles': 'scientist-goggles',
 'astronaut': 'astronaut', 'scientist': 'scientist', 'cat-bear': 'cat-bear',
 'postech-selfie': 'postech-selfie',
}
SOURCE_VERSIONS = {'postech-selfie': 'v02', 'cat-bear': 'v02'}
TARGET_TRIANGLES = 100_000
MAX_TEXTURE = 1024
out.mkdir(parents=True, exist_ok=True); report.mkdir(parents=True, exist_ok=True)
records = []

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def triangles(objects):
 return sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objects)
def bounds(objects):
 points = [o.matrix_world @ Vector(p) for o in objects for p in o.bound_box]
 return Vector(tuple(min(p[i] for p in points) for i in range(3))), Vector(tuple(max(p[i] for p in points) for i in range(3)))
def stage_info(path):
 stage = Usd.Stage.Open(str(path))
 box = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_, UsdGeom.Tokens.render]).ComputeWorldBound(stage.GetPseudoRoot()).ComputeAlignedRange()
 up = UsdGeom.GetStageUpAxis(stage)
 assert up in (UsdGeom.Tokens.y, UsdGeom.Tokens.z)
 vertical = 1 if up == UsdGeom.Tokens.y else 2
 assert UsdGeom.GetStageMetersPerUnit(stage) == 1
 return dict(heightMeters=box.GetSize()[vertical], groundMeters=box.GetMin()[vertical],
             triangles=sum(sum(max(int(n)-2,0) for n in UsdGeom.Mesh(p).GetFaceVertexCountsAttr().Get()) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)))
def studio():
 s=bpy.context.scene; s.render.engine='CYCLES'; s.cycles.samples=20; s.cycles.use_denoising=True
 s.render.resolution_x=360; s.render.resolution_y=480; s.render.resolution_percentage=100
 s.render.film_transparent=True; s.render.image_settings.file_format='PNG';s.render.image_settings.color_mode='RGBA'
 s.view_settings.view_transform='AgX'
 s.world=bpy.data.worlds.new('Studio');s.world.use_nodes=True
 bg=next(n for n in s.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.72,.74,.70,1);bg.inputs[1].default_value=.65
 for name,loc,power,size in [('Key',(-3,-4,4),450,5),('Fill',(3,-1,3),180,4),('Rim',(0,4,3),240,4)]:
  d=bpy.data.lights.new(name,'AREA');d.energy=power;d.size=size
  o=bpy.data.objects.new(name,d);s.collection.objects.link(o);o.location=loc
  o.rotation_euler=(Vector((0,0,.75))-o.location).to_track_quat('-Z','Y').to_euler()
 c=bpy.data.cameras.new('Camera');cam=bpy.data.objects.new('Camera',c);s.collection.objects.link(cam);s.camera=cam
 c.type='ORTHO';c.ortho_scale=1.72
 return s,cam

def render(s,cam,path,angle=0):
 target=Vector((0,0,.75));cam.location=target+Vector((4*math.sin(angle),-4*math.cos(angle),.10))
 cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();s.render.filepath=str(path)
 bpy.ops.render.render(write_still=True)

for name, style in SOURCES.items():
 if selected and name not in selected: continue
 version=SOURCE_VERSIONS.get(name, 'v01')
 src=work/f'meshy_output/oi-library/characters/oi-{style}-150cm-{version}.usdz'
 source_hash=sha(src); source_info=stage_info(src)
 dest=out/f'wardrobe-costume-{name}.usdz'
 bpy.ops.wm.read_factory_settings(use_empty=True)
 s=bpy.context.scene;s.unit_settings.system='METRIC';s.unit_settings.scale_length=1
 with tempfile.TemporaryDirectory(prefix='oi-mobile-costume-') as temp:
  scratch=Path(temp)
  with zipfile.ZipFile(src) as z:
   root=z.namelist()[0]
   # Only read archives from the local authored library, reject unexpected archive paths.
   for member in z.namelist():
    assert not Path(member).is_absolute() and '..' not in Path(member).parts
   z.extractall(scratch)
  for image in scratch.rglob('*'):
   if image.suffix.lower() in ('.png','.jpg','.jpeg'):
    subprocess.run(['sips','-Z',str(MAX_TEXTURE),str(image)],check=True,stdout=subprocess.DEVNULL)
  input_file=scratch/'resized.usdz'
  assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(scratch/root)),str(input_file))
  bpy.ops.wm.usd_import(filepath=str(input_file))
  objects=[o for o in s.objects if o.type=='MESH']
  assert objects and not any(o.type=='ARMATURE' for o in s.objects), 'Rigged assets need a separate optimization path'
  for o in objects:
   world=o.matrix_world.copy();o.parent=None;o.matrix_world=world
   bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
   bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
  original_bounds=bounds(objects); before_tri=triangles(objects)
  s,cam=studio()
  render(s,cam,report/f'{name}-before.png')
  for o in objects:
   bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
   # Meshy may split coincident vertices along UV seams. Weld positions before
   # collapse so the two sides cannot simplify independently and open cracks.
   # Per-corner UVs/material assignments remain separate.
   bm=bmesh.new();bm.from_mesh(o.data)
   bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000002)
   bm.verts.ensure_lookup_table();bm.verts.index_update()
   uv=bm.loops.layers.uv.active;protected=set()
   for edge in bm.edges:
    seam=not edge.is_manifold
    if not seam and uv:
     left,right=edge.link_loops
     a,b=left[uv].uv,left.link_loop_next[uv].uv
     c,d=right[uv].uv,right.link_loop_next[uv].uv
     if left.vert!=right.vert:c,d=d,c
     seam=(a-c).length_squared>1e-12 or (b-d).length_squared>1e-12
    if seam:protected.update(v.index for v in edge.verts)
   bm.to_mesh(o.data);bm.free();o.data.update()
   group=o.vertex_groups.new(name='PreserveUVSeams')
   group.add(list(range(len(o.data.vertices))),1,'REPLACE')
   if protected:group.add(list(protected),0,'REPLACE')
   # Collapse preserves the source UVs/materials, without re-generating the character.
   if before_tri > TARGET_TRIANGLES:
    # Leave room for independently simplified meshes and protected seam boundaries.
    modifier=o.modifiers.new('Mobile detail','DECIMATE');modifier.ratio=(TARGET_TRIANGLES-500)/before_tri;modifier.use_collapse_triangulate=True
    modifier.vertex_group=group.name;modifier.vertex_group_factor=1000
    bpy.ops.object.modifier_apply(modifier=modifier.name)
   # Imported split normals describe the dense source, not the reduced topology.
   if o.data.has_custom_normals:bpy.ops.mesh.customdata_custom_splitnormals_clear()
   for polygon in o.data.polygons:polygon.use_smooth=True
  after_bounds=bounds(objects)
  # Reject changes that noticeably move feet, resize props or alter silhouette bounds.
  assert max(abs(after_bounds[j][i]-original_bounds[j][i]) for j in range(2) for i in range(3)) < .005
  bpy.ops.object.select_all(action='DESELECT')
  for o in objects:o.select_set(True)
  bpy.ops.wm.usd_export(filepath=str(dest),selected_objects_only=True,export_textures=True,export_materials=True,
    export_uvmaps=True,export_normals=True,relative_paths=True,root_prim_path='/OiCostume',
    convert_orientation=True,export_animation=False,meters_per_unit=1,export_custom_properties=False,
    convert_world_material=False,export_lights=False,export_cameras=False)
  info=stage_info(dest)
  stage=Usd.Stage.Open(str(dest))
  assert UsdGeom.GetStageUpAxis(stage) == UsdGeom.Tokens.y
  assert not any(p.GetTypeName()=='Camera' or str(p.GetTypeName()).endswith('Light') for p in stage.Traverse()), 'Do not package studio lighting'
  assert all(max(im.size)<=MAX_TEXTURE for im in bpy.data.images if im.type=='IMAGE' and im.has_data), 'Texture budget exceeded'
  assert abs(info['heightMeters']-1.5)<.005 and abs(info['groundMeters'])<.005
  assert info['triangles']<=TARGET_TRIANGLES+100
  _,_,unresolved=UsdUtils.ComputeAllDependencies(str(dest));assert not unresolved,unresolved
  with zipfile.ZipFile(dest) as z:
   assert z.testzip() is None and all(i.compress_type==zipfile.ZIP_STORED for i in z.infolist())
  assert dest.stat().st_size<12*1024*1024, 'Revisit asset budget'
  render(s,cam,report/f'{name}-front.png')
  render(s,cam,report/f'{name}-side.png',math.pi/2)
  render(s,cam,report/f'{name}-back.png',math.pi)
  subprocess.run(['sips','-Z','256',str(report/f'{name}-front.png'),'--out',str(out/f'oi-costume-{name}.png')],check=True,stdout=subprocess.DEVNULL)
 assert source_hash==sha(src), 'Source must stay unchanged'
 record=dict(id=name,source=str(src.relative_to(work)),sourceSHA256=source_hash,sourceBytes=src.stat().st_size,
  sourceTriangles=source_info['triangles'],bytes=dest.stat().st_size,sha256=sha(dest),maxTextureDimension=MAX_TEXTURE,**info)
 records.append(record);(report/'manifest.json').write_text(json.dumps(records,indent=2)+'\n')
 print('MOBILE_COSTUME_READY '+json.dumps(record),flush=True)
