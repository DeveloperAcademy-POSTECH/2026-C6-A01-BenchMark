"""Remove green garment texture contamination, preserving skin and UVs.
Blender -b --python repair_uniform_garment.py -- SOURCE.usdz OUTPUT.usdz REPORT_DIR
"""
from pathlib import Path
import sys,json,hashlib,zipfile,shutil,struct
import bpy,numpy as np
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Sdf
sys.path.insert(0,str(Path(__file__).resolve().parent))
from apply_cat_skin import pixels,linear
source,output,root=map(lambda p:Path(p).resolve(),sys.argv[sys.argv.index('--')+1:]);assert source!=output
profiles={
 '240973e9a686f56348a9de8b0164f284b4c004838341a2c82202cb00dd63a86f':'school-uniform-trousers',
 '47a3b767f752054337f0cc807c0ac5da17447f6be229bfc7c200290a0ef3a751':'scientist-goggles'}
expected=hashlib.sha256(source.read_bytes()).hexdigest();assert expected in profiles,'Use the approved source model';name=profiles[expected]
root.mkdir(parents=True,exist_ok=True);work=root/'work';work.mkdir(exist_ok=True)
with zipfile.ZipFile(source) as z:
 assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in z.namelist());z.extractall(work);layer=work/z.namelist()[0]
stage=Usd.Stage.Open(str(layer));mesh=max([UsdGeom.Mesh(p) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh)],key=lambda m:len(m.GetFaceVertexCountsAttr().Get()));material=UsdShade.MaterialBindingAPI(mesh).ComputeBoundMaterial()[0];surface=material.ComputeSurfaceSource()[0];file=UsdShade.Shader(surface.GetInput('diffuseColor').GetConnectedSource()[0].GetPrim()).GetInput('file');old_path=file.Get().path
bpy.ops.wm.read_factory_settings(use_empty=True);image=bpy.data.images.load(str(work/old_path.lstrip('./')));N=image.size[0];assert image.size[1]==N==2048;original=pixels(image).reshape(N,N,3).copy()
points=np.asarray(mesh.GetPointsAttr().Get());faces=np.asarray(mesh.GetFaceVertexIndicesAttr().Get()).reshape(-1,3);matrix=UsdGeom.XformCache().GetLocalToWorldTransform(mesh.GetPrim());world=np.asarray([matrix.Transform(tuple(map(float,p))) for p in points]);wt=world[faces];uvvar=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st');uv=np.asarray(uvvar.ComputeFlattened());uvtris=uv.reshape(-1,3,2) if uvvar.GetInterpolation()=='faceVarying' else uv[faces]
# Large connected green surface components are exposed cucumber skin. Tiny
# isolated green triangles on the suit are contamination, not skin.
from collections import deque
samples=[]
for weights in [[1/3]*3,[.6,.2,.2],[.2,.6,.2],[.2,.2,.6]]:
 q=np.einsum('fij,i->fj',uvtris,np.asarray(weights));samples.append(original[np.clip((q[:,1]*N).astype(int),0,N-1),np.clip((q[:,0]*N).astype(int),0,N-1)])
samples=np.median(samples,axis=0);green_faces=(samples[:,1]>samples[:,0]*1.12)&(samples[:,1]>samples[:,2]*1.12)&(samples[:,1]>.1)
vertex_faces=[[] for _ in points]
for i,face in enumerate(faces):
 if green_faces[i]:
  for v in face:vertex_faces[v].append(i)
seen=np.zeros(len(faces),bool);skin_faces=np.zeros_like(seen)
for i in np.flatnonzero(green_faces):
 if seen[i]:continue
 q=deque([i]);seen[i]=True;component=[]
 while q:
  face=q.popleft();component.append(face)
  for v in faces[face]:
   for j in vertex_faces[v]:
    if not seen[j]:seen[j]=True;q.append(j)
 if len(component)>=100:
  skin_faces[component]=True;w=wt[component].reshape(-1,3);print('PROTECTED_SKIN_COMPONENT',len(component),w.min(0).tolist(),w.max(0).tolist(),flush=True)
if name=='school-uniform-trousers':
 # Use a face's dominant material, not individual scratch pixels, to keep
 # trouser texels gray and prevent a false black band at the trouser hem.
 palette=np.array([[5,25,54],[63,63,63],[14,11,9]],float)/255
 face_labels=1+np.argmin(((samples[:,None,:]-palette[None,:,:])**2).sum(2),axis=1)
 centers=wt.mean(1);face_labels[(centers[:,1]<.36)&(face_labels==1)]=2
 face_labels[(samples.min(1)>.60)|((samples.max(1)-samples.min(1)<.06)&(samples.mean(1)>.30)&(centers[:,1]>.42))]=0
 # A contaminated face inherits its nearby clean garment's material category.
 from mathutils.kdtree import KDTree
 ids=np.flatnonzero((~green_faces)&(~skin_faces)&(centers[:,1]<.88));material_tree=KDTree(len(ids))
 for i,j in enumerate(ids):material_tree.insert(tuple(centers[j]),int(j))
 material_tree.balance()
 for j in np.flatnonzero(green_faces&~skin_faces&(centers[:,1]<.88)):
  _,donor,_=material_tree.find(tuple(centers[j]));face_labels[j]=face_labels[donor]
else:
 centers=wt.mean(1);face_labels=np.full(len(faces),3,np.uint8)
 face_labels[(centers[:,1]>.41)|(samples.min(1)>.60)]=1
 red=(samples[:,0]>samples[:,1]*1.2)&(samples[:,0]>samples[:,2]*1.12)
 shirt=(np.abs(centers[:,0])<.10)&(centers[:,2]>.10)&(centers[:,1]>.41)&(samples.mean(1)<.50)
 face_labels[(red&(centers[:,1]>.38))|shirt]=2
 from mathutils.kdtree import KDTree
 ids=np.flatnonzero((~green_faces)&(~skin_faces)&(centers[:,1]<.88));tree=KDTree(len(ids))
 for i,j in enumerate(ids):tree.insert(tuple(centers[j]),int(j))
 tree.balance()
 for j in np.flatnonzero(green_faces&~skin_faces&(centers[:,1]<.88)):
  _,donor,_=tree.find(tuple(centers[j]));face_labels[j]=face_labels[donor]

if name=='scientist-goggles':
 # The original colored hem is part of the shirt, not the white coat.
 core=(np.abs(centers[:,0])<.10)&(centers[:,2]>.13)&(centers[:,1]>.425)&(centers[:,1]<.75)&(samples.min(1)<.60)
 face_labels[core]=2
clothclass=np.zeros((N,N),np.uint8)
cloth=np.zeros((N,N),bool);protected=np.zeros_like(cloth);worldmap=np.zeros((N,N,3),np.float32)
for index,(tri,w) in enumerate(zip(uvtris*N,wt)):
 x0,y0=np.maximum(0,np.floor(tri.min(0)).astype(int));x1,y1=np.minimum(N-1,np.ceil(tri.max(0)).astype(int))
 if x1<x0 or y1<y0:continue
 yy,xx=np.mgrid[y0:y1+1,x0:x1+1];v=np.stack((xx+.5,yy+.5),-1)-tri[0];a,b=tri[1]-tri[0],tri[2]-tri[0];det=a[0]*b[1]-a[1]*b[0]
 if abs(det)<1e-9:continue
 u=(v[...,0]*b[1]-v[...,1]*b[0])/det;t=(a[0]*v[...,1]-a[1]*v[...,0])/det;inside=(u>=0)&(t>=0)&(u+t<=1);p=w[0]+u[...,None]*(w[1]-w[0])+t[...,None]*(w[2]-w[0]);garment=(p[...,1]<.88)&~skin_faces[index];sl=np.s_[y0:y1+1,x0:x1+1];cloth[sl]|=inside&garment;protected[sl]|=inside&~garment;worldmap[sl][inside]=p[inside];clothclass[sl][inside]=face_labels[index]
# Include unoccupied filter padding but never a texel used by exposed skin.
region=cloth.copy()
for _ in range(2):
 p=np.pad(region,1);region=np.maximum.reduce([p[y:y+N,x:x+N] for y in range(3) for x in range(3)])
padding_protected=np.pad(protected,1);protected=np.maximum.reduce([padding_protected[y:y+N,x:x+N] for y in range(3) for x in range(3)])
region&=~protected
r,g,b=np.moveaxis(original,-1,0);green=(g>r*1.12)&(g>b*1.12)&(g-r>.012)&(g-b>.012);
if name=='scientist-goggles':green=(g-r>.008)&(g-b>.008)
bad=green&region
assert 0<bad.sum()<60000,('Unexpected garment mask',int(bad.sum()))
rgb=original.copy();known=region&~green;pending=bad.copy()
for iteration in range(16):
 if not pending.any():break
 padded=np.pad(rgb,((1,1),(1,1),(0,0)));valid=np.pad(known,1);summed=np.zeros_like(rgb);weight=np.zeros((N,N),np.float32)
 for dy,dx in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]:
  v=valid[1+dy:1+dy+N,1+dx:1+dx+N];summed+=padded[1+dy:1+dy+N,1+dx:1+dx+N]*v[...,None];weight+=v
 filled=pending&(weight>0);rgb[filled]=summed[filled]/weight[filled,None];known|=filled;pending&=~filled
# Some tiny UV islands contain only the contaminated texel. Restore these
# from nearby clean cloth on the same physical garment rather than another UV island.
if (pending&cloth).any():
 from mathutils.kdtree import KDTree
 centers=wt.mean(1);donors=(~green_faces)&(~skin_faces)&(centers[:,1]<.88);ids=np.flatnonzero(donors);tree=KDTree(len(ids))
 for i,j in enumerate(ids):tree.insert(tuple(centers[j]),int(j))
 tree.balance()
 for y,x in zip(*np.nonzero(pending&cloth)):
  _,j,distance=tree.find(tuple(worldmap[y,x]));assert distance<.03,('No nearby cloth donor',distance);rgb[y,x]=samples[j];known[y,x]=True;pending[y,x]=False
# Propagate restored island colors into its unused filter padding.
for _ in range(4):
 if not pending.any():break
 padded=np.pad(rgb,((1,1),(1,1),(0,0)));valid=np.pad(known,1);summed=np.zeros_like(rgb);weight=np.zeros((N,N),np.float32)
 for dy,dx in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]:
  v=valid[1+dy:1+dy+N,1+dx:1+dx+N];summed+=padded[1+dy:1+dy+N,1+dx:1+dx+N]*v[...,None];weight+=v
 filled=pending&(weight>0);rgb[filled]=summed[filled]/weight[filled,None];known|=filled;pending&=~filled
assert not (pending&cloth).any()
bad&=~pending

green_repaired=int(bad.sum())
material_colors={}
if name=='school-uniform-trousers':
 # Plain uniform cloth should have one fabric hue. Keep its normal/roughness
 # texture while suppressing source-image green/brown scratch colors in albedo.
 editable=cloth&~protected;brightness=rgb.mean(2);neutral=rgb.max(2)-rgb.min(2)<.06
 white=(rgb.min(2)>.60);button=neutral&(brightness>.30)&(worldmap[:,:,1]>.42)
 blue=(rgb[:,:,2]>rgb[:,:,0]*1.15)&(rgb[:,:,2]>rgb[:,:,1]*1.12)
 labels=np.where(editable,clothclass,0).astype(np.uint8)
 # Carry the garment category into unused UV filter padding, avoiding skin.
 for _ in range(2):
  p=np.pad(labels,1);candidates=np.maximum.reduce([p[y:y+N,x:x+N] for y in range(3) for x in range(3)]);fill=region&(labels==0)&~cloth;labels[fill]=candidates[fill]
 material_colors={}
 for label in [1,2,3]:
  mask=labels==label;donor=editable&(labels==label)&~green
  if label==1:donor&=blue
  elif label==2:donor&=neutral
  else:donor&=brightness<.18
  assert donor.sum()>100
  color=np.median(rgb[donor],axis=0);material_colors[str(label)]=[round(float(x*255),2) for x in color]
  factor=1+np.clip((brightness-color.mean())/max(float(color.mean()),.02),-.03,.03)*.3
  rgb[mask]=np.clip(color*factor[mask,None],0,1);bad|=mask
if name=='scientist-goggles':
 editable=cloth&~protected;brightness=rgb.mean(2);labels=np.where(editable,clothclass,0).astype(np.uint8)
 for _ in range(2):
  p=np.pad(labels,1);candidates=np.maximum.reduce([p[y:y+N,x:x+N] for y in range(3) for x in range(3)]);fill=region&(labels==0)&~cloth;labels[fill]=candidates[fill]
 x,y,z=np.moveaxis(worldmap,-1,0)
 detail_region=(x>.06)&(x<.26)&(y>.50)&(y<.80)&(z>.03)
 red_detail=(original[:,:,0]>original[:,:,1]*1.2)&(original[:,:,0]>original[:,:,2]*1.1)
 dark_detail=(original.max(2)<.65)&(original.max(2)-original.min(2)<.10)
 keep_detail=detail_region&~green
 for label in [1,2,3]:
  mask=(labels==label)&~keep_detail;donor=editable&(labels==label)&~green&~detail_region
  if label==1:donor&=rgb.min(2)>.70
  elif label==2:donor&=(rgb[:,:,0]>rgb[:,:,1]*1.3)&(np.abs(x)<.1)&(y>.42)
  else:donor&=(rgb.max(2)-rgb.min(2)<.04)&(y>.23)&(y<.42)
  assert donor.sum()>100
  color=np.median(rgb[donor],axis=0);material_colors[str(label)]=[round(float(v*255),2) for v in color]
  factor=1+np.clip((brightness-color.mean())/max(float(color.mean()),.02),-.03,.03)*.3
  # Keep shoes unchanged and smoothly retain the bottom trouser shading.
  blend=np.clip((y-.18)/.06,0,1);blend[~cloth]=1;mask&=blend>0
  rgb[mask]=rgb[mask]*(1-blend[mask,None])+np.clip(color*factor[mask,None],0,1)*blend[mask,None];bad|=mask
np.save(root/'garment-edit-mask.npy',bad)

bpy.ops.mesh.primitive_plane_add(size=2);mat=bpy.data.materials.new('Clean garment albedo');mat.use_nodes=True;bpy.context.object.data.materials.append(mat);nodes,links=mat.node_tree.nodes,mat.node_tree.links;nodes.clear();data=bpy.data.images.new('Repaired cloth',width=N,height=N,alpha=False,float_buffer=True);data.colorspace_settings.name='Non-Color';rgba=np.ones((N,N,4),np.float32);rgba[:,:,:3]=linear(rgb);data.pixels.foreach_set(rgba.ravel());tex=nodes.new('ShaderNodeTexImage');tex.image=data;tex.interpolation='Closest';emit=nodes.new('ShaderNodeEmission');links.new(tex.outputs[0],emit.inputs[0]);out=nodes.new('ShaderNodeOutputMaterial');links.new(emit.outputs[0],out.inputs[0]);result=bpy.data.images.new('Uniform clean color',width=N,height=N,alpha=False);result.colorspace_settings.name='sRGB';target=nodes.new('ShaderNodeTexImage');target.image=result;nodes.active=target;scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=1;scene.render.bake.margin=0;bpy.ops.object.bake(type='EMIT');new_path='./textures/'+('uniform-clean-garment-color.png' if name=='school-uniform-trousers' else 'scientist-goggles-clean-garment-color.png');dest=work/new_path.lstrip('./');result.filepath_raw=str(dest);result.file_format='PNG';result.save();new=pixels(bpy.data.images.load(str(dest))).reshape(N,N,3)
error=float(np.abs(new[~bad]-original[~bad]).max());print('OUTSIDE_ERROR',error,'original',original[1000,1000].tolist(),'new',new[1000,1000].tolist(),flush=True);assert error<=1/255+1e-6;assert np.abs(new[protected]-original[protected]).max()<=1/255+1e-6
if name=='scientist-goggles':assert np.abs(new[keep_detail]-original[keep_detail]).max()<=1/255+1e-6,'Logo/pen pixels changed'
file.Set(Sdf.AssetPath(new_path));stage.GetRootLayer().Save();compact=work/'compact.usdc';assert stage.GetRootLayer().Export(str(compact));shutil.move(compact,layer)
if output.exists():output.unlink()
assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer)),str(output))
before=Usd.Stage.Open(str(source));after=Usd.Stage.Open(str(output))
for p in before.Traverse():
 q=after.GetPrimAtPath(p.GetPath());assert q and q.GetTypeName()==p.GetTypeName()
 for a in p.GetAttributes():
  b=q.GetAttribute(a.GetName());x,y=a.Get(),b.Get()
  if a.GetPath()==file.GetAttr().GetPath():assert x.path==old_path and y.path==new_path
  elif isinstance(x,Sdf.AssetPath):assert x.path==y.path
  else:assert x==y,str(a.GetPath())
  assert a.GetConnections()==b.GetConnections()
 for rel in p.GetRelationships():assert rel.GetTargets()==q.GetRelationship(rel.GetName()).GetTargets()
with zipfile.ZipFile(source) as a,zipfile.ZipFile(output) as b:
 assert b.testzip() is None
 for n in a.namelist()[1:]:
  if n in b.namelist():assert a.read(n)==b.read(n)
 raw=output.read_bytes()
 for item in b.infolist():
  x,y=struct.unpack_from('<HH',raw,item.header_offset+26);assert item.compress_type==zipfile.ZIP_STORED and (item.header_offset+30+x+y)%64==0
assert output.stat().st_size<12*1024*1024
report={'id':name,'sourceRevision':'9586630e38e5588029d451a18ee9861b336045e3','sourceSHA256':expected,'outputSHA256':hashlib.sha256(output.read_bytes()).hexdigest(),'bytes':output.stat().st_size,'greenGarmentPixelsRepaired':green_repaired,'garmentTexelsNormalized':int(bad.sum()),'garmentHueNormalized':True,'materialColorsRGB':material_colors,'outsideEditMaxError':error,'geometryUVsNormalsBindingsUnchanged':True,'otherMaterialChannelsUnchanged':True,'skinProtected':True,'decorationsProtected':name=='scientist-goggles','colorFile':new_path.lstrip('./')};(root/'garment-report.json').write_text(json.dumps(report,indent=2)+'\n');print('GARMENT_REPAIRED',report,flush=True)
