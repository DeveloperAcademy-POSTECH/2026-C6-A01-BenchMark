"""Render lit and color-only face crops for a reviewed costume.
Blender -b --python render_costume_faces.py -- ID SOURCE.usdz OUTPUT_DIR
"""
import bpy,sys,json,hashlib
from pathlib import Path
from mathutils import Vector
name,source,dest=sys.argv[sys.argv.index('--')+1:];source=Path(source).resolve();dest=Path(dest).resolve();dest.mkdir(parents=True,exist_ok=True)
config=json.loads(Path(__file__).with_name('costume-face-cleanup-config.json').read_text())['models'][name]
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.wm.usd_import(filepath=str(source))
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True;scene.view_settings.view_transform='Standard';scene.world=bpy.data.worlds.new('Neutral studio');scene.world.color=(.5,.5,.5)
for location,power,size in [((-3,-4,5),450,4),((3,-2,3),200,3),((0,3,4),300,3)]:
 bpy.ops.object.light_add(type='AREA',location=location);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(Vector((0,0,.8))-light.location).to_track_quat('-Z','Y').to_euler()
target=Vector((0,0,1.12));bpy.ops.object.camera_add(location=target+Vector((0,-4,.05)));camera=bpy.context.object;camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=.82;scene.camera=camera
left,top=config['left'],config['top'];width,height=config['fieldSize'];scene.render.resolution_x=1440;scene.render.resolution_y=1920;scene.render.resolution_percentage=100;scene.render.use_border=True;scene.render.use_crop_to_border=True;scene.render.border_min_x=left/480;scene.render.border_max_x=(left+width/3)/480;scene.render.border_min_y=1-(top+height/3)/640;scene.render.border_max_y=1-top/640;scene.render.image_settings.file_format='PNG';scene.render.filepath=str(dest/(name+'-lit.png'));bpy.ops.render.render(write_still=True)
for material in bpy.data.materials:
 if not material.use_nodes:continue
 for node in list(material.node_tree.nodes):
  if node.type=='BSDF_PRINCIPLED':
   emission=material.node_tree.nodes.new('ShaderNodeEmission')
   if node.inputs['Base Color'].is_linked:material.node_tree.links.new(node.inputs['Base Color'].links[0].from_socket,emission.inputs['Color'])
   else:emission.inputs['Color'].default_value=node.inputs['Base Color'].default_value
   output=next(n for n in material.node_tree.nodes if n.type=='OUTPUT_MATERIAL');material.node_tree.links.new(emission.outputs[0],output.inputs['Surface'])
scene.cycles.use_denoising=False;scene.render.filepath=str(dest/(name+'-albedo.png'));bpy.ops.render.render(write_still=True)
report={'id':name,'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest()}
for label in ['lit','albedo']:report[label+'SHA256']=hashlib.sha256((dest/(name+'-'+label+'.png')).read_bytes()).hexdigest()
(dest/(name+'-render.json')).write_text(json.dumps(report,indent=2)+'\n');print('FACE_RENDERED',name,flush=True)
