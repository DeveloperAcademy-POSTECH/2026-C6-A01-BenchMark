"""Sharpen only the ORIGINAL sleeve POSTECH word on the reviewed jackets.
Blender -b --python repair_postech_marks.py -- SOURCE.usdz OUTPUT.usdz REPORT_DIR
Preserves the original letter shapes/weight, chest P, seal, and all non-color maps.
"""
from pathlib import Path
import bpy,numpy as np,sys,zipfile,json,hashlib,struct,zlib
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Sdf
source,output,r=map(lambda p:Path(p).resolve(),sys.argv[sys.argv.index('--')+1:])
assert source!=output
approved={'wardrobe-postech-long.usdz':'de92783cc5bc56db5ab602344405bfcc9aef5d7a54bfca27fede6216c026e0c1','wardrobe-postech-shorts.usdz':'0e9103b301fcce518bc577780fa449b29dae4ec933ea10f6af9d3f93664b3798'}
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
source_sha=sha(source);assert source_sha in approved.values(),'Use the reviewed main 9586630 source'
model_name=next(k for k,v in approved.items() if v==source_sha)
r.mkdir(parents=True,exist_ok=True);work=r/'work';work.mkdir(exist_ok=True)
def write_png(path,rgb):
 data=np.rint(np.clip(rgb[::-1],0,1)*255).astype(np.uint8);h,w,ch=data.shape
 def chunk(t,b):return struct.pack('>I',len(b))+t+b+struct.pack('>I',zlib.crc32(t+b)&0xffffffff)
 path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2 if ch==3 else 6,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(b'\1'+np.concatenate([row[:1],row[1:]-row[:-1]]).tobytes() for row in data),9))+chunk(b'IEND',b''))
with zipfile.ZipFile(source) as archive:
 assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in archive.namelist())
 archive.extractall(work);root=work/archive.namelist()[0]
stage=Usd.Stage.Open(str(root));mesh=next(UsdGeom.Mesh(p) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh) and '/Top/' in str(p.GetPath()));mat=UsdShade.MaterialBindingAPI(mesh).ComputeBoundMaterial()[0];surf=mat.ComputeSurfaceSource()[0]
def texfield(channel):return UsdShade.Shader(surf.GetInput(channel).GetConnectedSource()[0].GetPrim()).GetInput('file')
N=2048
im=bpy.data.images.load(str(work/texfield('diffuseColor').Get().path.lstrip('./')));im.colorspace_settings.name='Non-Color';im.scale(N,N);rgba=np.array(im.pixels[:]).reshape(N,N,4);original=rgba.copy();out=rgba[:,:,:3].copy()
uvvar=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st');faces=np.array(mesh.GetFaceVertexIndicesAttr().Get()).reshape(-1,3);uv=np.array(uvvar.ComputeFlattened());uv=uv.reshape(-1,3,2) if uvvar.GetInterpolation()=='faceVarying' else uv[faces]
m=UsdGeom.XformCache().GetLocalToWorldTransform(mesh.GetPrim());p=np.array([m.Transform(tuple(v)) for v in mesh.GetPointsAttr().Get()]);p=p[:,[0,2,1]];p[:,1]*=-1;tris=p[faces]
# Separate the two sleeve panels from the connected burgundy torso.
q=uv.mean(1);c=original[np.clip((q[:,1]*N).astype(int),0,N-1),np.clip((q[:,0]*N).astype(int),0,N-1),:3]
def components(selected):
 vf=[[] for _ in p]
 for i,f in enumerate(faces):
  if selected[i]:
   for v in f:vf[v].append(i)
 seen=set();comps=[]
 for i in np.flatnonzero(selected):
  if i in seen:continue
  todo=[i];seen.add(i);comp=[]
  while todo:
   f=todo.pop();comp.append(f)
   for v in faces[f]:
    for j in vf[v]:
     if j not in seen:seen.add(j);todo.append(j)
  comps.append(comp)
 return sorted(comps,key=len,reverse=True)
red=(c[:,0]>c[:,1]*1.6)&(c[:,0]>c[:,2]*1.6)&(c[:,1]<.3)
body=np.zeros(len(faces),bool);body[components(red)[0]]=True
bodymap=np.zeros((N,N),bool)
wm=np.zeros((N,N,3),np.float32);used=np.zeros((N,N),bool)
for faceindex,(t,w) in enumerate(zip(uv*N,tris)):
 lo=np.maximum(0,np.floor(t.min(0)).astype(int));hi=np.minimum(N-1,np.ceil(t.max(0)).astype(int));x0,y0=lo;x1,y1=hi
 if x1<x0 or y1<y0:continue
 yy,xx=np.mgrid[y0:y1+1,x0:x1+1];v=np.stack((xx+.5,yy+.5),-1)-t[0];a,b=t[1]-t[0],t[2]-t[0];d=a[0]*b[1]-a[1]*b[0]
 if abs(d)<1e-10:continue
 u=(v[...,0]*b[1]-v[...,1]*b[0])/d;q=(a[0]*v[...,1]-a[1]*v[...,0])/d;inside=(u>=0)&(q>=0)&(u+q<=1);sl=np.s_[y0:y1+1,x0:x1+1];wm[sl][inside]=(w[0]+u[...,None]*(w[1]-w[0])+q[...,None]*(w[2]-w[0]))[inside];used[sl]|=inside;bodymap[sl][inside]=body[faceindex]
x,y,z=np.moveaxis(wm,-1,0)
def band(v,lo,hi,f=.006):return np.clip((v-lo)/f,0,1)*np.clip((hi-v)/f,0,1)
# Isolate the existing sleeve lettering and its faint color halo. The large
# connected burgundy torso is excluded even where it touches the sleeve.
L=band(-x,.185,.43)*band(z,.698,.835)*used*(~bodymap)
cream=np.median(out[(L>.9)&(out.min(2)>.75)],axis=0)
ink=np.median(out[(L>.9)&(out[:,:,0]<.65)&(out[:,:,1]<.20)&(out[:,:,0]>out[:,:,1]*2)],axis=0)
vector=cream-ink;length=float(np.dot(vector,vector))
alpha=np.clip(np.einsum('ijk,k->ij',cream-out,vector)/length,0,1)
# A symmetric transition keeps exactly the same 50% ink contour: no new font,
# stroke dilation, coordinate projection, or letter repositioning is used.
sharp=np.clip((alpha-.24)/.52,0,1);sharp=sharp*sharp*(3-2*sharp)
colored=(out[:,:,0]-out[:,:,1]>.025)&(out[:,:,0]-out[:,:,2]>.015)
edit=L*colored*(alpha>.035)
left_axis=-.243-(.79-z)*.35
theta=np.arctan2(x-left_axis,-y)
# Keep the real front word; remove its detached faded copy around the back.
ghost=np.clip((np.abs(theta)-1.35)/.25,0,1)*edit
sharp*=1-ghost
reconstructed=cream*(1-sharp[...,None])+ink*sharp[...,None]
out=out*(1-edit[...,None])+reconstructed*edit[...,None]
out=np.clip(out,0,1)
core=(L>.999)&colored&(ghost==0)
before_ink=core&(alpha>=.5)
after_alpha=np.clip(np.einsum('ijk,k->ij',cream-out,vector)/length,0,1)
after_ink=core&(after_alpha>=.5)
assert np.array_equal(before_ink,after_ink),'Original ink contour/weight moved'
assert before_ink.sum()>500
protected=used&(x>0)
assert np.max(np.abs(out[protected]-original[:,:,:3][protected]))==0
print('ORIGINAL_WORD',dict(cream=cream.tolist(),ink=ink.tolist(),inkPixels=int(before_ink.sum())),flush=True)
# Expand only into empty atlas texels for bilinear filtering at island seams.
known=used.copy();modified=edit>0
for _ in range(3):
 valid=np.pad(known,1);mods=np.pad(modified,1);colors=np.pad(out,((1,1),(1,1),(0,0)));sumc=np.zeros_like(out);count=np.zeros((N,N));newmod=np.zeros((N,N),bool)
 for dy,dx in [(0,1),(0,-1),(1,0),(-1,0)]:
  k=valid[1+dy:1+dy+N,1+dx:1+dx+N];sumc+=colors[1+dy:1+dy+N,1+dx:1+dx+N]*k[...,None];count+=k;newmod|=mods[1+dy:1+dy+N,1+dx:1+dx+N]
 fill=(~known)&(count>0)&newmod;out[fill]=sumc[fill]/count[fill,None];known|=fill;modified|=fill
write_png(work/'textures/postech-original-word-sharp.png',out)
write_png(r/'edit-mask.png',np.repeat(edit[:,:,None],3,axis=2))
outside_error=float(np.max(np.abs(out[~modified]-original[:,:,:3][~modified])));assert outside_error==0
texfield('diffuseColor').Set(Sdf.AssetPath('./textures/postech-original-word-sharp.png'))
stage.GetRootLayer().Save();assert not output.exists(),'Output already exists'
assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(root)),str(output))
before,after=Usd.Stage.Open(str(source)),Usd.Stage.Open(str(output))
allowed={str(texfield(c).GetAttr().GetPath()) for c in ['diffuseColor']}
assert {p.GetPath() for p in before.Traverse()}=={p.GetPath() for p in after.Traverse()}
for old in before.Traverse():
 new=after.GetPrimAtPath(old.GetPath());assert old.GetTypeName()==new.GetTypeName()
 for attr in old.GetAttributes():
  current=new.GetAttribute(attr.GetName());a,b=attr.Get(),current.Get()
  if str(attr.GetPath()) not in allowed:
   assert (a.path==b.path if isinstance(a,Sdf.AssetPath) else a==b),str(attr.GetPath())
  assert attr.GetConnections()==current.GetConnections()
 for rel in old.GetRelationships():assert rel.GetTargets()==new.GetRelationship(rel.GetName()).GetTargets()
with zipfile.ZipFile(source) as original_zip,zipfile.ZipFile(output) as final_zip:
 assert final_zip.testzip() is None
 for name in original_zip.namelist()[1:]:
  if name in final_zip.namelist():assert original_zip.read(name)==final_zip.read(name),name
 raw=output.read_bytes()
 for entry in final_zip.infolist():
  assert entry.compress_type==zipfile.ZIP_STORED
  namesize,extrasize=struct.unpack_from('<HH',raw,entry.header_offset+26)
  assert (entry.header_offset+30+namesize+extrasize)%64==0
bounds=UsdGeom.BBoxCache(Usd.TimeCode.Default(),['default','render']).ComputeWorldBound(after.GetDefaultPrim()).ComputeAlignedRange()
assert UsdGeom.GetStageUpAxis(after)=='Y' and UsdGeom.GetStageMetersPerUnit(after)==1 and abs(bounds.GetSize()[1]-1.5)<.005
report={'file':model_name,'scope':'original-sleeve-word-only','sourceSHA256':source_sha,'outputSHA256':sha(output),'bytes':output.stat().st_size,'heightMeters':bounds.GetSize()[1],'geometryUVsTransformsUnchanged':True,'skinMaterialsAndTexturesUnchanged':True,'onlyTopColorTextureChanged':True,'normalRoughnessMetallicUnchanged':True,'chestPAndSealUnchanged':True,'protectedMarkColorMaxError':float(np.max(np.abs(out[protected]-original[:,:,:3][protected]))),'outsideEditMaxError':outside_error,'colorTextureSize':[N,N],'detachedGhostTexels':int(np.count_nonzero(ghost>.5)),'originalInkPixels':int(before_ink.sum()),'outputInkPixels':int(after_ink.sum()),'inkContourChangedPixels':int(np.count_nonzero(before_ink!=after_ink)),'textures':{'postech-original-word-sharp.png':sha(work/'textures/postech-original-word-sharp.png')}}
(r/'report.json').write_text(json.dumps(report,indent=2)+'\n');print('POSTECH_WORD_READY',json.dumps(report),flush=True)
