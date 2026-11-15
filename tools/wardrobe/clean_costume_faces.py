"""Bake reviewed smooth eye/mouth silhouettes onto a costume's original UVs.
Blender -b --python clean_costume_faces.py -- ID SOURCE.usdz OUTPUT.usdz REPORT_DIR
An optional CONFIG.json argument after REPORT_DIR selects a follow-up field set.
Sources are recoverable from costume-face-cleanup-config.json's sourceRevision.
Only diffuse color changes. Geometry, normals, UVs, bindings and other maps stay exact.
"""
import sys,json,hashlib,zipfile,shutil,struct
from pathlib import Path
import bpy,numpy as np
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Sdf
sys.path.insert(0,str(Path(__file__).resolve().parent))
from apply_cat_skin import pixels,linear
from face_material_rules import light_frame_guard,dark_selfie_frame_guard
name=sys.argv[sys.argv.index('--')+1]
args=sys.argv[sys.argv.index('--')+2:];assert len(args) in [3,4]
source,output,root=map(lambda p:Path(p).resolve(),args[:3])
config_path=Path(args[3]).resolve() if len(args)==4 else Path(__file__).with_name('costume-face-cleanup-config.json')
config=json.loads(config_path.read_text());cfg=config['models'][name]
assert config['baseRGB']==[151,211,106] and config['eyeRGB']==[12,12,12] and config['mouthRGB']==[32,69,42]
fields_path=config_path.parent/config.get('fieldsFile','costume-face-fields.npz')
assert hashlib.sha256(fields_path.read_bytes()).hexdigest()==config['fieldsSHA256']
assert source!=output and hashlib.sha256(source.read_bytes()).hexdigest()==cfg['sourceSHA256']
root.mkdir(parents=True,exist_ok=True);work=root/'work';work.mkdir(exist_ok=True)
with zipfile.ZipFile(source) as archive:
 assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in archive.namelist());archive.extractall(work);layer=work/archive.namelist()[0]
stage=Usd.Stage.Open(str(layer));meshes=[UsdGeom.Mesh(p) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)]
main=max(meshes,key=lambda m:len(m.GetFaceVertexCountsAttr().Get()));material=UsdShade.MaterialBindingAPI(main).ComputeBoundMaterial()[0];surface=material.ComputeSurfaceSource()[0];color_shader=UsdShade.Shader(surface.GetInput('diffuseColor').GetConnectedSource()[0].GetPrim());file_input=color_shader.GetInput('file');old_path=file_input.Get().path
bpy.ops.wm.read_factory_settings(use_empty=True)
image=bpy.data.images.load(str(work/old_path.lstrip('./')));size=image.size[0];assert image.size[1]==size and size in [1024,2048]
original=pixels(image).reshape(size,size,3).copy();N=2048
if size==1024:original=np.repeat(np.repeat(original,2,0),2,1)
fields=np.load(fields_path,allow_pickle=False);data={label:np.asarray(fields[name+'__'+label],np.float32) for label in ['clear','eyes','mouth']}
H,W=data['clear'].shape
assert all(a.shape==(H,W) and np.isfinite(a).all() and a.min()>=0 and a.max()<=1 for a in data.values())

def project(p):
 return np.stack((240+p[...,0]*(640/.82),320-((p[...,1]-1.12)*.999921884-p[...,2]*.0124990236)*(640/.82)),axis=-1)

def sample(field,p):
 x=(p[...,0]-cfg['left'])*3-.5;y=(p[...,1]-cfg['top'])*3-.5;valid=(x>=0)&(x<W-1)&(y>=0)&(y<H-1)
 ix=np.clip(np.floor(x).astype(int),0,W-2);iy=np.clip(np.floor(y).astype(int),0,H-2);fx=np.clip(x-ix,0,1);fy=np.clip(y-iy,0,1)
 return ((field[iy,ix]*(1-fx)+field[iy,ix+1]*fx)*(1-fy)+(field[iy+1,ix]*(1-fx)+field[iy+1,ix+1]*fx)*fy)*valid

# Sparse eye geometry may have no vertex at the pupil center. Sample the
# projected triangle surfaces as well as vertices to find its front cap.
eye_gates={}
if cfg.get('eyeDepthGates'):
 points=np.asarray(main.GetPointsAttr().Get());indices=np.asarray(main.GetFaceVertexIndicesAttr().Get()).reshape(-1,3);matrix=UsdGeom.XformCache().GetLocalToWorldTransform(main.GetPrim());world=np.asarray([matrix.Transform(tuple(map(float,p))) for p in points]);triangles=world[indices];screen=project(triangles);vertices=project(world)
 a=screen[:,1]-screen[:,0];b=screen[:,2]-screen[:,0];det=a[:,0]*b[:,1]-a[:,1]*b[:,0];nondegenerate=np.abs(det)>1e-12
 for key,settings in cfg['eyeDepthGates'].items():
  center=np.asarray(cfg['eyes'][int(key)]['center']);central=(np.linalg.norm(vertices-center,axis=1)<=4)&(world[:,2]>0);peak=float(world[central,2].max()) if central.any() else -np.inf
  for dx in range(-4,5):
   for dy in range(-4,5):
    if dx*dx+dy*dy>16:continue
    v=center+np.array([dx,dy])-screen[:,0];u=np.divide(v[:,0]*b[:,1]-v[:,1]*b[:,0],det,out=np.zeros(len(det)),where=nondegenerate);t=np.divide(a[:,0]*v[:,1]-a[:,1]*v[:,0],det,out=np.zeros(len(det)),where=nondegenerate);inside=nondegenerate&(u>=0)&(t>=0)&(u+t<=1)
    z=triangles[:,0,2]+u*(triangles[:,1,2]-triangles[:,0,2])+t*(triangles[:,2,2]-triangles[:,0,2]);valid=inside&(z>0)
    if valid.any():peak=max(peak,float(z[valid].max()))
  assert np.isfinite(peak),'Pupil surface not found'
  eye_gates[key]=dict(settings,peakZ=peak,center=center.tolist())

gate_regions={key:np.zeros((N,N),bool) for key in eye_gates}
coverage=np.zeros((N,N),np.float32);masks={k:np.ones_like(coverage) for k in data};cache=UsdGeom.XformCache()
for mesh in meshes:
 points=np.asarray(mesh.GetPointsAttr().Get());faces=np.asarray(mesh.GetFaceVertexIndicesAttr().Get()).reshape(-1,3);matrix=cache.GetLocalToWorldTransform(mesh.GetPrim());world=np.asarray([matrix.Transform(tuple(map(float,p))) for p in points]);wtris=world[faces]
 uvvar=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st');uv=np.asarray(uvvar.ComputeFlattened());uvtris=uv.reshape(-1,3,2) if uvvar.GetInterpolation()=='faceVarying' else uv[faces]
 for i,tri in enumerate(uvtris*N):
  x0,y0=np.maximum(0,np.floor(tri.min(0)).astype(int));x1,y1=np.minimum(N-1,np.ceil(tri.max(0)).astype(int))
  if x1<x0 or y1<y0:continue
  yy,xx=np.mgrid[y0:y1+1,x0:x1+1];v=np.stack((xx+.5,yy+.5),-1)-tri[0];a,b=tri[1]-tri[0],tri[2]-tri[0];det=a[0]*b[1]-a[1]*b[0]
  if abs(det)<1e-9:continue
  u=(v[...,0]*b[1]-v[...,1]*b[0])/det;t=(a[0]*v[...,1]-a[1]*v[...,0])/det;inside=(u>=0)&(t>=0)&(u+t<=1);sl=np.s_[y0:y1+1,x0:x1+1];coverage[sl]+=inside
  if wtris[i].max(0)[2]<=0:
   for mask in masks.values():mask[sl][inside]=0
   continue
  projected=project(wtris[i]);low=projected.min(0);high=projected.max(0)
  if high[0]<cfg['left'] or low[0]>cfg['left']+W/3 or high[1]<cfg['top'] or low[1]>cfg['top']+H/3:
   for mask in masks.values():mask[sl][inside]=0
   continue
  positions=wtris[i,0]+u[...,None]*(wtris[i,1]-wtris[i,0])+t[...,None]*(wtris[i,2]-wtris[i,0]);p=project(positions)
  for label,field in data.items():
   values=sample(field,p)*(positions[...,2]>0)
   if label=='eyes':
    for key,gate in eye_gates.items():
     near=np.linalg.norm(p-np.asarray(gate['center']),axis=-1)<24
     support=np.clip((positions[...,2]-(gate['peakZ']-gate['offset']))/gate['feather'],0,1)
     values*=np.where(near,support,1)
     gate_regions[key][sl][inside&near]=True
   if label=='eyes':
    for surface_eye in cfg.get('surfaceEyeBases',[]):
     dx=p[...,0]-surface_eye['center'][0];dy=p[...,1]-surface_eye['center'][1];coef=surface_eye['coefficients'];base=coef[0]+coef[1]*dx+coef[2]*dy+coef[3]*dx*dx+coef[4]*dx*dy+coef[5]*dy*dy
     near=np.hypot(dx,dy)<surface_eye['radius']
     support=np.clip((positions[...,2]-base-surface_eye['thresholdMeters'])/surface_eye['featherMeters'],0,1)
     values*=np.where(near,support,1)
   view=masks[label][sl]
   view[inside]=np.minimum(view[inside],values[inside])
# Every channel uses the most protective coverage across shared UVs.
# Frame protection below must not suppress clearing of green pigment blends.
# A pupil texel reused by surrounding skin must never paint that skin black.
# Every mesh participates, and fields never extend over triangle bounding boxes.
for label,mask in masks.items():
 mask[coverage==0]=0
 values=np.zeros_like(mask);count=np.zeros_like(mask)
 for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:
  valid=np.roll(np.roll(coverage>0,dy,0),dx,1);values+=np.roll(np.roll(mask,dy,0),dx,1)*valid;count+=valid
 padding=(coverage==0)&(count>0);mask[padding]=values[padding]/count[padding]
# Keep a texel of skin between ink and a depth-excluded surface. Bilinear
# filtering otherwise reads the adjacent pupil texel across a UV boundary.
for key,gate in eye_gates.items():
 for _ in range(gate.get('filterInsetTexels',0)):
  mask=masks['eyes'];padded=np.pad(mask,1,mode='constant');eroded=np.minimum.reduce([padded[dy:dy+N,dx:dx+N] for dy in range(3) for dx in range(3)])
  region=gate_regions[key];masks['eyes'][region]=eroded[region]
for _ in range(config.get('eyeFilterInsetTexels',0)):
 mask=masks['eyes'];padded=np.pad(mask,1,mode='constant');masks['eyes']=np.minimum.reduce([padded[dy:dy+N,dx:dx+N] for dy in range(3) for dx in range(3)])
# Preserve white/silver eyewear where the clearing halo approaches a frame.
white=light_frame_guard(original[:,:,0],original[:,:,1],original[:,:,2])
masks['clear'][white]=0
if name=='postech-selfie':masks['clear'][dark_selfie_frame_guard(original[:,:,0],original[:,:,1],original[:,:,2])]=0
for label,mask in masks.items():np.save(root/(label+'-mask.npy'),mask)

bpy.ops.mesh.primitive_plane_add(size=2);mat=bpy.data.materials.new('Reviewed clean face');mat.use_nodes=True;bpy.context.object.data.materials.append(mat);nodes,links=mat.node_tree.nodes,mat.node_tree.links;nodes.clear();tex=nodes.new('ShaderNodeTexImage');tex.image=image;tex.interpolation='Closest';final=tex.outputs['Color']
for label,rgb in [('clear',config['baseRGB']),('eyes',config['eyeRGB']),('mouth',config['mouthRGB'])]:
 mask_image=bpy.data.images.new(label,width=N,height=N,alpha=False);mask_image.colorspace_settings.name='Non-Color';rgba=np.ones((N,N,4),np.float32);rgba[:,:,:3]=masks[label][:,:,None];mask_image.pixels.foreach_set(rgba.ravel());selector=nodes.new('ShaderNodeTexImage');selector.image=mask_image;selector.interpolation='Closest';mix=nodes.new('ShaderNodeMixRGB');links.new(selector.outputs[0],mix.inputs[0]);links.new(final,mix.inputs[1]);mix.inputs[2].default_value=(*linear(np.asarray(rgb)/255),1);final=mix.outputs[0]
emission=nodes.new('ShaderNodeEmission');links.new(final,emission.inputs['Color']);out=nodes.new('ShaderNodeOutputMaterial');links.new(emission.outputs[0],out.inputs['Surface']);result=bpy.data.images.new('Clean face albedo',width=N,height=N,alpha=False);result.colorspace_settings.name='sRGB';target=nodes.new('ShaderNodeTexImage');target.image=result;nodes.active=target;scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=1;scene.render.bake.margin=0;bpy.ops.object.bake(type='EMIT');new_path='./textures/'+config.get('colorFile','clean-face-albedo.png');new_file=work/new_path.lstrip('./');result.filepath_raw=str(new_file);result.file_format='PNG';result.save()
file_input.Set(Sdf.AssetPath(new_path));stage.GetRootLayer().Save();compact=work/'compact.usdc';assert stage.GetRootLayer().Export(str(compact));shutil.move(compact,layer)
if output.exists():output.unlink()
assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer)),str(output))
before=Usd.Stage.Open(str(source));after=Usd.Stage.Open(str(output))
for p in before.Traverse():
 q=after.GetPrimAtPath(p.GetPath());assert q and p.GetTypeName()==q.GetTypeName()
 for attr in p.GetAttributes():
  a,b=attr.Get(),q.GetAttribute(attr.GetName()).Get()
  if attr.GetPath()==file_input.GetAttr().GetPath():assert a.path==old_path and b.path==new_path
  elif isinstance(a,Sdf.AssetPath):assert a.path==b.path
  else:assert a==b,str(attr.GetPath())
  assert attr.GetConnections()==q.GetAttribute(attr.GetName()).GetConnections()
 for rel in p.GetRelationships():assert rel.GetTargets()==q.GetRelationship(rel.GetName()).GetTargets()
with zipfile.ZipFile(source) as a,zipfile.ZipFile(output) as b:
 assert b.testzip() is None
 for entry in a.namelist()[1:]:
  if entry in b.namelist():assert a.read(entry)==b.read(entry)
 raw=output.read_bytes()
 for item in b.infolist():
  assert item.compress_type==zipfile.ZIP_STORED;x,y=struct.unpack_from('<HH',raw,item.header_offset+26);assert (item.header_offset+30+x+y)%64==0
new=pixels(bpy.data.images.load(str(new_file))).reshape(N,N,3);changed=np.maximum.reduce(list(masks.values()))>0;error=float(np.abs(new[~changed]-original[~changed]).max());assert error<=1/255+1e-6
assert np.max(np.abs(new[masks['eyes']>.999]-np.asarray(config['eyeRGB'])/255))<=1/255+1e-6
report={'id':name,'cleanupVersion':config['cleanupVersion'],'sharedUVConflictsGuarded':True,'oldPigmentCleared':True,'eyeDepthGates':eye_gates,'surfaceEyeBases':cfg.get('surfaceEyeBases',[]),'sourceRevision':config['sourceRevision'],'sourceSHA256':cfg['sourceSHA256'],'outputSHA256':hashlib.sha256(output.read_bytes()).hexdigest(),'bytes':output.stat().st_size,'colorTextureSize':N,'fieldsSHA256':config['fieldsSHA256'],'eyeColor':'#0C0C0C','mouthColor':'#20452A','geometryUVsNormalsBindingsUnchanged':True,'otherMaterialChannelsUnchanged':True,'outsideFaceMaxError':error}
assert report['bytes']<12*1024*1024
assert hashlib.sha256(source.read_bytes()).hexdigest()==cfg['sourceSHA256']
(root/'face-report.json').write_text(json.dumps(report,indent=2)+'\n');print('FACE_CLEANED',report,flush=True)
