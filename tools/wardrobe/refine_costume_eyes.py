"""Bake precise black pupils into an already repaired costume's material.
Blender -b --python refine_costume_eyes.py -- ID SOURCE.usdz OUTPUT.usdz REPORT_DIR
Only the diffuse texture in two small eye neighborhoods changes. Meshes,
UVs, normals, clothing and every other material channel are compared exactly.
"""
import sys,json,hashlib,zipfile,shutil,struct
from pathlib import Path
import bpy,numpy as np
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Sdf
sys.path.insert(0,str(Path(__file__).resolve().parent))
from apply_cat_skin import linear,pixels
name=sys.argv[sys.argv.index('--')+1]
source,output,root=map(lambda x:Path(x).resolve(),sys.argv[sys.argv.index('--')+2:])
assert source!=output
source_hashes={'sportswear': 'd9c5e5205deea3564dcfcacfb6610033fdcf1585a217bb249fbea0c25a3bfdc4', 'school-uniform': 'b37f2c1a439876849955af53ea59280903bfb6b92d41e171c4ae9626fb62194d'}
assert hashlib.sha256(source.read_bytes()).hexdigest()==source_hashes[name], 'Use the matching repaired costume source'
regions={
 'sportswear':[(191,422,12.0,12.4),(289,422,12.0,12.4)],
 'school-uniform':[(196.4,344.4,13.3,14.0),(283.0,363.6,13.3,14.0)]
}[name]
root.mkdir(parents=True,exist_ok=True);work=root/'work';work.mkdir(exist_ok=True)
with zipfile.ZipFile(source) as z:
 assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in z.namelist())
 z.extractall(work);layer=work/z.namelist()[0]
stage=Usd.Stage.Open(str(layer));prim=next(p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh));mesh=UsdGeom.Mesh(prim)
mat=UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0];surface=mat.ComputeSurfaceSource()[0]
color_shader=UsdShade.Shader(surface.GetInput('diffuseColor').GetConnectedSource()[0].GetPrim())
old_path=color_shader.GetInput('file').Get().path;old_image=work/old_path.lstrip('./')
bpy.ops.wm.read_factory_settings(use_empty=True)
image=bpy.data.images.load(str(old_image));width,height=image.size;assert width==height==1024
original=pixels(image).copy()
points=np.asarray(mesh.GetPointsAttr().Get());faces=np.asarray(mesh.GetFaceVertexIndicesAttr().Get()).reshape(-1,3)
world=np.asarray([UsdGeom.XformCache().GetLocalToWorldTransform(prim).Transform(tuple(map(float,p))) for p in points])
uvvar=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st');uv=np.asarray(uvvar.ComputeFlattened());tris=uv.reshape(-1,3,2) if uvvar.GetInterpolation()=='faceVarying' else uv[faces]
def project(p):
 return np.stack((240+p[...,0]*(640/.82),320-((p[...,1]-1.12)*.999921884-p[...,2]*.0124990236)*(640/.82)),axis=-1)
# Project actual mesh surface back into its authored UVs. Analytic coverage
# produces a smooth pupil boundary without accepting the source's dark smears.
coverage=np.zeros((height,width),np.float32);clear=np.zeros_like(coverage);pupil=np.zeros_like(coverage)
wtris=world[faces];projected=project(wtris);lo=projected.min(1);hi=projected.max(1)
selected=np.zeros(len(faces),bool)
for cx,cy,rx,ry in regions:selected|=(lo[:,0]<cx+27)&(hi[:,0]>cx-27)&(lo[:,1]<cy+27)&(hi[:,1]>cy-27)
selected&=wtris.mean(1)[:,2]>0
for index in np.flatnonzero(selected):
 tri=tris[index]*width;x0,y0=np.maximum(0,np.floor(tri.min(0)).astype(int));x1,y1=np.minimum(width-1,np.ceil(tri.max(0)).astype(int))
 if x1<x0 or y1<y0:continue
 yy,xx=np.mgrid[y0:y1+1,x0:x1+1];v=np.stack((xx+.5,yy+.5),axis=-1)-tri[0]
 a,b=tri[1]-tri[0],tri[2]-tri[0];det=a[0]*b[1]-a[1]*b[0]
 if abs(det)<1e-9:continue
 u=(v[...,0]*b[1]-v[...,1]*b[0])/det;t=(a[0]*v[...,1]-a[1]*v[...,0])/det
 inside=(u>=0)&(t>=0)&(u+t<=1)
 pos=wtris[index,0]+u[...,None]*(wtris[index,1]-wtris[index,0])+t[...,None]*(wtris[index,2]-wtris[index,0]);p=project(pos)
 c=np.zeros(inside.shape,np.float32);e=np.zeros_like(c)
 for cx,cy,rx,ry in regions:
  r=np.sqrt(((p[...,0]-cx)/rx)**2+((p[...,1]-cy)/ry)**2)
  e=np.maximum(e,np.clip((1-r)*min(rx,ry)+.5,0,1))
  radius=np.sqrt((p[...,0]-cx)**2+(p[...,1]-cy)**2)
  c=np.maximum(c,np.clip(26-radius,0,1))
 sl=np.s_[y0:y1+1,x0:x1+1];coverage[sl]+=inside;clear[sl]=np.maximum(clear[sl],c);pupil[sl]+=e*inside
pupil/=np.maximum(coverage,1)
# Extend the clearing mask into unused UV padding. Ribbon eye islands need
# matching pupil padding at seams; sportswear pupils deliberately stay unpadded
# to prevent the previous black fringe on adjacent skin.
for mask in ((clear,pupil) if name=='school-uniform' else (clear,)):
 for _ in range(2):
  values=np.zeros_like(mask);count=np.zeros_like(mask)
  for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:
   valid=np.roll(np.roll(coverage>0,dy,0),dx,1);values+=np.roll(np.roll(mask,dy,0),dx,1)*valid;count+=valid
  fill=(coverage==0)&(count>0);mask[fill]=values[fill]/count[fill]
np.save(root/'clear-mask.npy',clear);np.save(root/'pupil-mask.npy',pupil)
assert np.count_nonzero(pupil>.99)>25
bpy.ops.mesh.primitive_plane_add(size=2);material=bpy.data.materials.new('Precise eye material bake');material.use_nodes=True;bpy.context.object.data.materials.append(material)
n,l=material.node_tree.nodes,material.node_tree.links;n.clear();tex=n.new('ShaderNodeTexImage');tex.image=image
final=tex.outputs['Color']
for label,mask,rgb in [('Eye neighborhood',clear,[151,211,106]),('Pupil',pupil,[12,12,12])]:
 m=bpy.data.images.new(label,width=width,height=height,alpha=False);m.colorspace_settings.name='Non-Color';data=np.ones((height,width,4),np.float32);data[:,:,:3]=mask[:,:,None];m.pixels.foreach_set(data.ravel())
 selector=n.new('ShaderNodeTexImage');selector.image=m;selector.interpolation='Closest'
 mix=n.new('ShaderNodeMixRGB');l.new(selector.outputs['Color'],mix.inputs[0]);l.new(final,mix.inputs[1]);mix.inputs[2].default_value=(*linear(np.array(rgb)/255),1);final=mix.outputs[0]
emission=n.new('ShaderNodeEmission');l.new(final,emission.inputs['Color']);out=n.new('ShaderNodeOutputMaterial');l.new(emission.outputs[0],out.inputs['Surface'])
result=bpy.data.images.new('Clean pupil albedo',width=width,height=height,alpha=False);result.colorspace_settings.name='sRGB';target=n.new('ShaderNodeTexImage');target.image=result;n.active=target
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=1;scene.render.bake.margin=0
bpy.ops.object.bake(type='EMIT');dest=work/'textures/precise-black-eyes.png';result.filepath_raw=str(dest);result.file_format='PNG';result.save()
new_path='./textures/precise-black-eyes.png';color_shader.GetInput('file').Set(Sdf.AssetPath(new_path));stage.GetRootLayer().Save();compact=work/'compact.usdc';assert stage.GetRootLayer().Export(str(compact));shutil.move(compact,layer)
if output.exists():output.unlink()
assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer)),str(output))
before=Usd.Stage.Open(str(source));after=Usd.Stage.Open(str(output))
for p in before.Traverse():
 q=after.GetPrimAtPath(p.GetPath());assert q and p.GetTypeName()==q.GetTypeName()
 for attr in p.GetAttributes():
  a,b=attr.Get(),q.GetAttribute(attr.GetName()).Get()
  if attr.GetPath()==color_shader.GetInput('file').GetAttr().GetPath():assert a.path==old_path and b.path==new_path
  elif isinstance(a,Sdf.AssetPath):assert a.path==b.path
  else:assert a==b,str(attr.GetPath())
  assert attr.GetConnections()==q.GetAttribute(attr.GetName()).GetConnections()
 for rel in p.GetRelationships():assert rel.GetTargets()==q.GetRelationship(rel.GetName()).GetTargets()
with zipfile.ZipFile(source) as a,zipfile.ZipFile(output) as b:
 assert b.testzip() is None
 for entry in a.namelist()[1:]:
  if entry in b.namelist():assert a.read(entry)==b.read(entry)
 raw=output.read_bytes()
 for entry in b.infolist():
  assert entry.compress_type==zipfile.ZIP_STORED
  x,y=struct.unpack_from('<HH',raw,entry.header_offset+26);assert (entry.header_offset+30+x+y)%64==0
b=pixels(bpy.data.images.load(str(dest)));outside=clear.ravel()==0;error=float(np.abs(original[outside]-b[outside]).max());assert error<=1/255+1e-6
assert np.max(np.abs(b[pupil.ravel()>.999]-12/255))<=1/255+1e-6
report={'id':name,'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'outputSHA256':hashlib.sha256(output.read_bytes()).hexdigest(),'bytes':output.stat().st_size,'eyeColor':'#0C0C0C','eyeRegions':regions,'outsideEyeMaxError':error,'geometryUVsNormalsBindingsUnchanged':True,'otherMaterialChannelsUnchanged':True,'pupilPixels':int((pupil>.99).sum())}
assert report['bytes']<12*1024*1024
(root/'eye-refinement-report.json').write_text(json.dumps(report,indent=2)+'\n');print('EYES_REFINED',report,flush=True)
