"""Repair six costume skin materials and black eyes, preserving clothing and geometry.
Blender -b --python repair_costume_skin.py -- COSTUME_ID ORIGINAL.usdz OUTPUT.usdz REPORT_DIR
Uses the reviewed fresh-cucumber-bright4 palette. The source is never edited.
UV skin selection protects uniform pixels; welded geometric normals remove skin
seam shading without moving vertices. Photo UV bindings must be regenerated.
"""
import bpy,numpy as np,sys,json,zipfile,hashlib,shutil,struct
from pathlib import Path
from pxr import Usd,UsdShade,UsdGeom,UsdUtils,Sdf,Vt
costume_id=sys.argv[sys.argv.index('--')+1]
source_path,output,root=map(lambda p:Path(p).resolve(),sys.argv[sys.argv.index('--')+2:])
root_name=f'wardrobe-costume-{costume_id}.usdc'
eye_regions={
 'baseball':[(196,417,21,21),(292,417,21,21)],
 'cowboy':[(192,352,20,20),(282,375,19,20)],
 'farmer':[(197,375,20,21),(287,381,20,21)],
 'postech-selfie':[(190,341,19,19),(282,350,20,20)],
 'sportswear':[(191,422,21,22),(289,422,21,22)],
 'martial-arts':[(209,349,21,21),(297,375,20,21)],
}[costume_id]
mouth_regions={'baseball':(244,461,43,25),'cowboy':(234,406,39,28),'farmer':(242,425,39,22),'postech-selfie':(232,387,37,21),'sportswear':(240,467,42,23),'martial-arts':(249,408,41,27)}
repo=Path(__file__).resolve().parents[2]
assert source_path != output
source_hashes={'baseball': 'd03975a81f288f81b1a58acda94015a5f7c765ef6358f36bbbeb1ebdde2b8366', 'farmer': '14b8b329487860b4670b61821a4f09e33ecd90e92f7b63e58b5d1090f2163e04', 'martial-arts': '8bae51994b0f04f8f8725a552b0c20fe63ec154216c5d2d3a824e67e1d9d3b82', 'sportswear': '1ccdd1102fd88f2d3b78d78f06d220ef89b8c70182e3a9bdd74121f5e9ee0806', 'cowboy': '8df8b76e676c68f88a916ac1e58ce9021ed4c453c5725818bfb291df875eafd5', 'postech-selfie': '3232941a9a1b392a4ed0a48a3c105e0e750c73368a5177a84ced4b7ea6c4d92e'}
assert hashlib.sha256(source_path.read_bytes()).hexdigest()==source_hashes[costume_id], 'Use the unmodified costume source'
root.mkdir(parents=True,exist_ok=True);source=root/'source';source.mkdir(exist_ok=True)
with zipfile.ZipFile(source_path) as z:
 assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in z.namelist())
 z.extractall(source)
work=root/'work';shutil.copytree(source,work,dirs_exist_ok=True)
sys.path.insert(0,str(repo/'tools/wardrobe'))
from apply_cat_skin import green_mask,pixels,linear
color=source/'textures/extracted_image_1.jpg'
reference={'base':(np.array([151,211,106])/255).tolist(),'stripe':(np.array([55,108,60])/255).tolist()}
report={'palette':reference,'roughness':155/255,'metallic':0,'maps':{}}
mask_cache=None
eye_cache=None
mouth_cache=None
def mask_node(nodes,original=False):
 global mask_cache,eye_cache,mouth_cache
 image=bpy.data.images.load(str(color));rgb=pixels(image)
 if mask_cache is None:
  mask_cache=np.zeros((1024,1024),dtype=bool)
  st=Usd.Stage.Open(str(source/root_name))
  prim=next(p for p in st.Traverse() if p.IsA(UsdGeom.Mesh));mesh=UsdGeom.Mesh(prim)
  points=np.asarray(mesh.GetPointsAttr().Get());faces=np.asarray(mesh.GetFaceVertexIndicesAttr().Get()).reshape(-1,3)
  matrix=UsdGeom.XformCache().GetLocalToWorldTransform(prim)
  world=np.array([matrix.Transform(tuple(map(float,p))) for p in points])
  uvvar=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st');uv=np.asarray(uvvar.ComputeFlattened())
  tris=uv.reshape(-1,3,2) if uvvar.GetInterpolation()=='faceVarying' else uv[faces]
  center=tris.mean(1);c=rgb.reshape(1024,1024,3)[np.clip((center[:,1]*1024).astype(int),0,1023),np.clip((center[:,0]*1024).astype(int),0,1023)]
  center3=world[faces].mean(1);x,y,z=center3.T
  head_top,stem_bottom={
   'baseball':(1.17,1.31),'cowboy':(1.27,1.39),'farmer':(1.27,1.35),
   'postech-selfie':(1.39,1.39),'sportswear':(1.39,1.39),'martial-arts':(1.40,1.40),
  }[costume_id]
  head_zone=(y>.60)&(y<head_top)&(np.abs(x)<.245)
  stem=(y>stem_bottom)
  limbs=((np.abs(x)>.18)&(y>.25)&(y<1.05))|(y<.23)
  anatomy=head_zone|stem|limbs
  head=head_zone&(c[:,1]>c[:,0]*1.02)&(c[:,1]>c[:,2]*1.35)&(c[:,1]>.15)
  skin_faces=anatomy&(((c[:,1]>c[:,0]*1.18)&(c[:,1]>c[:,2]*1.5)&(c[:,1]>.25))|head)
  eye_cache=np.zeros((1024,1024),dtype=bool);mouth_cache=np.zeros_like(eye_cache)
  # Orthographic face camera matches the neutral preview: USD Y-up, front +Z.
  for face_index,tri in enumerate(tris*1024):
   x0,y0=np.maximum(0,np.floor(tri.min(0)).astype(int));x1,y1=np.minimum(1023,np.ceil(tri.max(0)).astype(int))
   if x1<x0 or y1<y0:continue
   yy,xx=np.mgrid[y0:y1+1,x0:x1+1];v=np.stack((xx+.5,yy+.5),axis=-1)-tri[0]
   a,b=tri[1]-tri[0],tri[2]-tri[0];det=a[0]*b[1]-a[1]*b[0]
   if abs(det)<1e-9:continue
   u=(v[:,:,0]*b[1]-v[:,:,1]*b[0])/det;t=(a[0]*v[:,:,1]-a[1]*v[:,:,0])/det
   inside=(u>=0)&(t>=0)&(u+t<=1)
   if skin_faces[face_index]:mask_cache[y0:y1+1,x0:x1+1]|=inside
   w=world[faces[face_index]]
   if w.mean(0)[2]<=0 or w.mean(0)[1]<.85:continue
   positions=w[0]+u[:,:,None]*(w[1]-w[0])+t[:,:,None]*(w[2]-w[0])
   px=240+positions[:,:,0]*(640/.82)
   py=320-((positions[:,:,1]-1.12)*.999921884-positions[:,:,2]*.0124990236)*(640/.82)
   selected=np.zeros(inside.shape,dtype=bool)
   for cx,cy,rx,ry in eye_regions:selected|=((px-cx)/rx)**2+((py-cy)/ry)**2<=1
   pigment=rgb.reshape(1024,1024,3)[y0:y1+1,x0:x1+1]
   eye_cache[y0:y1+1,x0:x1+1]|=inside&selected&(pigment[:,:,1]<.48)
   cx,cy,rx,ry=mouth_regions[costume_id]
   mouth_cache[y0:y1+1,x0:x1+1]|=inside&(((px-cx)/rx)**2+((py-cy)/ry)**2<=1)&(pigment[:,:,1]<.48)
  # Extend skin padding across UV seams only near selected skin triangles.
  padded=mask_cache.copy()
  for dy in range(-3,4):
   for dx in range(-3,4):padded|=np.roll(np.roll(mask_cache,dy,axis=0),dx,axis=1)
  mask_cache|=padded&(green_mask(rgb)&(rgb[:,1]>.25)).reshape(1024,1024)
  mask_cache|=eye_cache|mouth_cache
  np.save(root/'skin-mask.npy',mask_cache);np.save(root/'eye-mask.npy',eye_cache);np.save(root/'mouth-mask.npy',mouth_cache)
  assert eye_cache.sum()>50,'Eye selection missing'
 data=np.ones((len(rgb),4),dtype=np.float32);data[:,:3]=(green_mask(rgb).reshape(-1,1) if original else mask_cache.reshape(-1,1))
 m=bpy.data.images.new('Skin selection',width=1024,height=1024,alpha=False);m.colorspace_settings.name='Non-Color';m.pixels.foreach_set(data.ravel())
 node=nodes.new('ShaderNodeTexImage');node.image=m;node.interpolation='Closest'
 return node

def bake_map(src,dest,replacement):
 bpy.ops.wm.read_factory_settings(use_empty=True)
 bpy.ops.mesh.primitive_plane_add(size=2)
 mat=bpy.data.materials.new('Selective skin material repair');mat.use_nodes=True;bpy.context.object.data.materials.append(mat)
 n,l=mat.node_tree.nodes,mat.node_tree.links;n.clear()
 tex=n.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(src));tex.image.colorspace_settings.name='sRGB' if replacement is None else 'Non-Color'
 mask=mask_node(n)
 mix=n.new('ShaderNodeMixRGB');l.new(mask.outputs[0],mix.inputs[0]);l.new(tex.outputs['Color'],mix.inputs[1])
 if replacement is None:
  sep=n.new('ShaderNodeSeparateColor');sep.mode='RGB'
  pigment=n.new('ShaderNodeTexImage');pigment.image=bpy.data.images.load(str(color));pigment.image.colorspace_settings.name='sRGB'
  l.new(pigment.outputs['Color'],sep.inputs['Color'])
  ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.interpolation='LINEAR'
  ramp.color_ramp.elements[0].position=float(linear(.50));ramp.color_ramp.elements[0].color=(*linear(reference['stripe']),1)
  ramp.color_ramp.elements[1].position=float(linear(.70));ramp.color_ramp.elements[1].color=(*linear(reference['base']),1)
  l.new(sep.outputs['Green'],ramp.inputs['Fac'])
  clean=n.new('ShaderNodeMixRGB');clean.inputs[1].default_value=(*linear(reference['base']),1);l.new(mask_node(n,original=True).outputs[0],clean.inputs[0]);l.new(ramp.outputs['Color'],clean.inputs[2]);l.new(clean.outputs[0],mix.inputs[2])
 else:mix.inputs[2].default_value=(*replacement,1)
 final=mix.outputs[0]
 if replacement is None:
  mouth_img=bpy.data.images.new('Smile selection',width=1024,height=1024,alpha=False);mouth_img.colorspace_settings.name='Non-Color'
  data=np.ones((1024*1024,4),np.float32);data[:,:3]=mouth_cache.reshape(-1,1);mouth_img.pixels.foreach_set(data.ravel())
  mouth=n.new('ShaderNodeTexImage');mouth.image=mouth_img;mouth.interpolation='Closest'
  smile=n.new('ShaderNodeMixRGB');l.new(mouth.outputs[0],smile.inputs[0]);l.new(final,smile.inputs[1]);smile.inputs[2].default_value=(*linear(np.array([32,69,42])/255),1);final=smile.outputs[0]

  eye_img=bpy.data.images.new('Eye selection',width=1024,height=1024,alpha=False);eye_img.colorspace_settings.name='Non-Color'
  data=np.ones((1024*1024,4),np.float32);data[:,:3]=eye_cache.reshape(-1,1);eye_img.pixels.foreach_set(data.ravel())
  eyes=n.new('ShaderNodeTexImage');eyes.image=eye_img;eyes.interpolation='Closest'
  eye_mix=n.new('ShaderNodeMixRGB');l.new(eyes.outputs[0],eye_mix.inputs[0]);l.new(final,eye_mix.inputs[1]);eye_mix.inputs[2].default_value=(*linear(np.array([12,12,12])/255),1);final=eye_mix.outputs[0]
 emission=n.new('ShaderNodeEmission');l.new(final,emission.inputs['Color'])
 output=n.new('ShaderNodeOutputMaterial');l.new(emission.outputs[0],output.inputs['Surface'])
 img=bpy.data.images.new('Clean skin channel',width=1024,height=1024,alpha=False);img.colorspace_settings.name='sRGB' if replacement is None else 'Non-Color'
 target=n.new('ShaderNodeTexImage');target.image=img;n.active=target
 scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=1;scene.render.bake.margin=0
 bpy.ops.object.bake(type='EMIT');img.filepath_raw=str(dest);img.file_format='PNG';img.save()

bake_map(color,work/'textures/clean-skin-color.png',None)
mapping={'./textures/extracted_image_1.jpg':'./textures/clean-skin-color.png'}
for channel,old,new,value in [
 ('normal','extracted_image_0.jpg','clean-skin-normal.png',(.5,.5,1)),
 ('roughness','extracted_image_2.jpg_roughness.png','clean-skin-roughness.png',(155/255,)*3),
 ('metallic','extracted_image_2.jpg_metallic.png','clean-skin-metallic.png',(0,0,0))]:
 bake_map(source/'textures'/old,work/'textures'/new,value);mapping['./textures/'+old]='./textures/'+new
stage=Usd.Stage.Open(str(work/root_name))
for prim in stage.Traverse():
 if prim.IsA(UsdShade.Shader):
  shader=UsdShade.Shader(prim)
  if shader.GetIdAttr().Get()=='UsdUVTexture':
   a=shader.GetInput('file');old=a.Get().path
   if old in mapping:a.Set(Sdf.AssetPath(mapping[old]))
p=next(p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh));m=UsdGeom.Mesh(p)
pts=np.asarray(m.GetPointsAttr().Get(),dtype=float);faces=np.asarray(m.GetFaceVertexIndicesAttr().Get()).reshape(-1,3)
uvvar=UsdGeom.PrimvarsAPI(m).GetPrimvar('st');uv=np.asarray(uvvar.ComputeFlattened());uv=uv.reshape(-1,3,2) if uvvar.GetInterpolation()=='faceVarying' else uv[faces]
image=bpy.data.images.load(str(color));a=np.empty(len(image.pixels),np.float32);image.pixels.foreach_get(a);a=a.reshape(image.size[1],image.size[0],4)
cent=uv.mean(1);rgb=a[np.clip((cent[:,1]*1024).astype(int),0,1023),np.clip((cent[:,0]*1024).astype(int),0,1023),:3]
skin=mask_cache[np.clip((cent[:,1]*1024).astype(int),0,1023),np.clip((cent[:,0]*1024).astype(int),0,1023)]
# Average geometric normals at coincident positions, independent of UV seams.
_,weld=np.unique(np.round(pts,5),axis=0,return_inverse=True)
f=pts[faces];cross=np.cross(f[:,1]-f[:,0],f[:,2]-f[:,0]);sums=np.zeros((max(weld)+1,3))
for i in range(3):np.add.at(sums,weld[faces[:,i]],cross)
sums/=np.maximum(np.linalg.norm(sums,axis=1)[:,None],1e-12)
old=np.asarray(m.GetNormalsAttr().Get(),dtype=float);interp=m.GetNormalsInterpolation()
print('NORMALS',old.shape,interp,'skin faces',int(skin.sum()),flush=True)
if interp=='faceVarying':
 new=old.reshape(-1,3,3).copy();new[skin]=sums[weld[faces[skin]]];new=new.reshape(-1,3)
else:
 new=old.copy();ids=np.unique(faces[skin]);new[ids]=sums[weld[ids]]
m.GetNormalsAttr().Set(Vt.Vec3fArray.FromNumpy(new.astype(np.float32)))

stage.GetRootLayer().Save()
# Re-export the crate to remove append-only superseded normal arrays.
compact=work/'compact.usdc';assert stage.GetRootLayer().Export(str(compact))
shutil.move(compact,work/root_name)
output.parent.mkdir(parents=True,exist_ok=True)
if output.exists():output.unlink()
assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(work/root_name)),str(output))
before=Usd.Stage.Open(str(source/root_name));after=Usd.Stage.Open(str(output))
for p in before.Traverse():
 q=after.GetPrimAtPath(p.GetPath());assert q and p.GetTypeName()==q.GetTypeName()
 for attr in p.GetAttributes():
  a,b=attr.Get(),q.GetAttribute(attr.GetName()).Get()
  if isinstance(a,Sdf.AssetPath) and a.path in mapping:assert b.path==mapping[a.path]
  elif attr.GetName()=='normals':
   assert np.array_equal(np.asarray(a).reshape(-1,3,3)[~skin],np.asarray(b).reshape(-1,3,3)[~skin]), 'Clothing normals changed'
  else:assert a==b,str(attr.GetPath())
  assert attr.GetConnections()==q.GetAttribute(attr.GetName()).GetConnections()
 for rel in p.GetRelationships():assert rel.GetTargets()==q.GetRelationship(rel.GetName()).GetTargets()
with zipfile.ZipFile(source_path) as original,zipfile.ZipFile(output) as edited:
 for name in original.namelist()[1:]:
  if name in edited.namelist():assert original.read(name)==edited.read(name)
 assert edited.testzip() is None
 raw=output.read_bytes()
 for item in edited.infolist():
  assert item.compress_type==zipfile.ZIP_STORED
  a,b=struct.unpack_from('<HH',raw,item.header_offset+26);assert (item.header_offset+30+a+b)%64==0
bpy.ops.wm.read_factory_settings(use_empty=True)
a=pixels(bpy.data.images.load(str(color)));b=pixels(bpy.data.images.load(str(work/'textures/clean-skin-color.png')))
mask=np.load(root/'skin-mask.npy').ravel();diff=np.abs(a[~mask]-b[~mask]);report['nonGreenColorMaxError']=float(diff.max());report['nonGreenColorMeanError']=float(diff.mean())
eye_values=b[np.load(root/'eye-mask.npy').ravel()];assert np.max(np.abs(eye_values-12/255))<=1/255+1e-6
report.update(id=costume_id,eyeColor='#0C0C0C',eyePixelCount=int(eye_cache.sum()),geometryUVsTransformsBindingsUnchanged=True,clothingNormalsUnchanged=True,skinNormalsRepaired=True,sourceArchiveUnchanged=True,outputSHA256=hashlib.sha256(output.read_bytes()).hexdigest(),bytes=output.stat().st_size)
assert report['nonGreenColorMaxError']<=1/255+1e-6
report['sourceSHA256']=hashlib.sha256(source_path.read_bytes()).hexdigest()
(root/'repair-report.json').write_text(json.dumps(report,indent=2));print('REPAIR_REPORT',report,flush=True)
