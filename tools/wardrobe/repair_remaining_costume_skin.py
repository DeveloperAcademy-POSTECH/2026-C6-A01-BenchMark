"""Repair remaining full-costume skin and precise facial features with Blender.
Usage: Blender -b --python repair_remaining_costume_skin.py -- ID SOURCE OUTPUT REPORT
Original geometry/UVs/bindings and garment normals are validated after packaging.
"""
import sys,json,zipfile,shutil,hashlib,struct
from pathlib import Path
import bpy,numpy as np
from pxr import Usd,UsdGeom,UsdShade,UsdUtils,Sdf,Vt
sys.path.insert(0,str(Path(__file__).resolve().parent))
from apply_cat_skin import pixels,linear,green_mask
name=sys.argv[sys.argv.index('--')+1];source,output,root=map(lambda p:Path(p).resolve(),sys.argv[sys.argv.index('--')+2:])
cfg=json.loads(Path(__file__).with_name('remaining-costume-skin-config.json').read_text())[name]
assert source!=output and hashlib.sha256(source.read_bytes()).hexdigest()==cfg['sourceSHA256']
root.mkdir(parents=True,exist_ok=True);work=root/'work';work.mkdir(exist_ok=True)
with zipfile.ZipFile(source) as z:
 assert all(not Path(n).is_absolute() and '..' not in Path(n).parts for n in z.namelist());z.extractall(work)
layer=work/cfg['rootLayer'];stage=Usd.Stage.Open(str(layer));prim=stage.GetPrimAtPath(cfg['meshPath']);mesh=UsdGeom.Mesh(prim)
mat=UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()[0];surface=mat.ComputeSurfaceSource()[0]
channels={}
for channel in ['diffuseColor','normal','roughness','metallic']:
 shader=UsdShade.Shader(surface.GetInput(channel).GetConnectedSource()[0].GetPrim());channels[channel]=(shader,shader.GetInput('file').Get().path)
bpy.ops.wm.read_factory_settings(use_empty=True)
color=work/channels['diffuseColor'][1].lstrip('./');img=bpy.data.images.load(str(color));rgb=pixels(img).copy();W,H=img.size;assert W==H==1024
size=cfg.get('textureSize',1024)
if size==2048:rgb=np.repeat(np.repeat(rgb.reshape(H,W,3),2,axis=0),2,axis=1).reshape(-1,3);W=H=size
pts=np.asarray(mesh.GetPointsAttr().Get(),dtype=float);faces=np.asarray(mesh.GetFaceVertexIndicesAttr().Get()).reshape(-1,3);matrix=UsdGeom.XformCache().GetLocalToWorldTransform(prim);world=np.asarray([matrix.Transform(tuple(map(float,p))) for p in pts]);wtri=world[faces]
uvvar=UsdGeom.PrimvarsAPI(mesh).GetPrimvar('st');uv=np.asarray(uvvar.ComputeFlattened());tris=uv.reshape(-1,3,2) if uvvar.GetInterpolation()=='faceVarying' else uv[faces]
def project(p):return np.stack((240+p[...,0]*(640/.82),320-((p[...,1]-1.12)*.999921884-p[...,2]*.0124990236)*(640/.82)),axis=-1)
cent=tris.mean(1);samples=rgb.reshape(H,W,3)[np.clip((cent[:,1]*H).astype(int),0,H-1),np.clip((cent[:,0]*W).astype(int),0,W-1)]
x,y,z=wtri.mean(1).T;screen=project(wtri.mean(1));ratio=cfg.get('greenRatio',1.18);blue_ratio=cfg.get('greenBlueRatio',1.5)
strong=(samples[:,1]>samples[:,0]*ratio)&(samples[:,1]>samples[:,2]*blue_ratio)&(samples[:,1]>.20)
if cfg.get('hood'):
 head=(y>.72)&(y<1.32)&(z>0)&(np.abs(x)<.25)
 stem=(y>1.32)&(np.abs(x)<.22)
 limbs=(np.abs(x)>.28)&(y>.30)&(y<.65)
else:
 head=(y>.60)&(y<1.39)&(np.abs(x)<.25)
 stem=y>1.36
 limbs=(np.abs(x)>.23)&(y>.30)&(y<1.03)
if name=='dinosaur':
 head=(y>.79)&(y<1.205)&(z>0)&(np.abs(x)<.26);stem=y>1.33;limbs=(np.abs(x)>.28)&(y>.40)&(y<.57)
if 'headOutline' in cfg:
 cx,cy,rx,ry=cfg['headOutline'];head&=((screen[:,0]-cx)/rx)**2+((screen[:,1]-cy)/ry)**2<1
anatomy=head|stem|limbs
if cfg['feet']:anatomy|=y<.30
stem_faces=(y>cfg['stemBottom'])&(np.abs(x)<.20)&(samples[:,1]>samples[:,0]*1.1)&(samples[:,1]>samples[:,2]*1.15)
if name=='raincoat':stem_faces&=samples[:,2]>samples[:,1]*.15
if name=='dinosaur':stem_faces&=samples[:,1]>samples[:,2]*3.5
skin_faces=(anatomy&strong)|stem_faces
if 'core' in cfg:
 cx,cy,rx,ry=cfg['core'];core=(((screen[:,0]-cx)/rx)**2+((screen[:,1]-cy)/ry)**2<1)&(z>0)
 if not cfg.get('helmet'):core&=(samples[:,1]>samples[:,0]*1.02)&(samples[:,1]>samples[:,2]*blue_ratio)
 if cfg.get('helmet'):skin_faces=(skin_faces&~head)|core
 else:skin_faces|=core
def inside_polygon(points,polygon):
 result=np.zeros(len(points),bool);px,py=points.T
 for a,b in zip(polygon,polygon[1:]+polygon[:1]):
  ax,ay=a;bx,by=b
  if abs(by-ay)>1e-8:result^=((ay>py)!=(by>py))&(px<(bx-ax)*(py-ay)/(by-ay)+ax)
 return result
if 'stemOutline' in cfg:
 stem_faces|=inside_polygon(screen,cfg['stemOutline']);skin_faces|=stem_faces
if 'facePolygons' in cfg:
 forced=np.zeros(len(faces),bool)
 for polygon in cfg['facePolygons']:forced|=inside_polygon(screen,polygon)&(z>0)
 if cfg.get('helmet'):skin_faces&=~head
 # Lens boundaries are rasterized per UV pixel below, including large faces.
if name=='raincoat':stem_faces=(y>1.335)&(np.abs(x)<.20)&(samples.max(axis=1)<.60)
skin_faces|=stem_faces
# Facial details use geometry coordinates rather than inheriting dark source pixels.
proj=project(wtri);lo=proj.min(1);hi=proj.max(1);feature_faces=np.zeros(len(faces),bool)
force_candidates=np.zeros(len(faces),bool)
for polygon in cfg.get('facePolygons',[]):
 box=np.asarray(polygon);low=box.min(0);high=box.max(0)
 force_candidates|=(lo[:,0]<=high[0])&(hi[:,0]>=low[0])&(lo[:,1]<=high[1])&(hi[:,1]>=low[1])&(z>0)
for cx,cy,rx,ry in cfg['eyes']:feature_faces|=(lo[:,0]<cx+25)&(hi[:,0]>cx-25)&(lo[:,1]<cy+25)&(hi[:,1]>cy-25)
x0m,y0m,x1m,y1m,depth,stroke=cfg['mouth'];mx=(x0m+x1m)/2;my=(y0m+y1m)/2+depth/2
feature_faces|=(lo[:,0]<x1m+14)&(hi[:,0]>x0m-14)&(lo[:,1]<max(y0m,y1m)+depth+14)&(hi[:,1]>min(y0m,y1m)-14)
feature_faces&=(z>0)&(y>.80)
stem_uv=np.zeros((H,W),np.float32)
protected=np.zeros((H,W),bool)
skin=np.zeros((H,W),np.float32);clear=np.zeros_like(skin);pupil=np.zeros_like(skin);smile=np.zeros_like(skin);coverage=np.zeros_like(skin)
curve=[]
for t in np.linspace(0,1,32):curve.append([x0m+(x1m-x0m)*t,y0m+(y1m-y0m)*t+depth*4*t*(1-t)])
for index in range(len(faces)):
 tri=tris[index]*W;xx0,yy0=np.maximum(0,np.floor(tri.min(0)).astype(int));xx1,yy1=np.minimum(W-1,np.ceil(tri.max(0)).astype(int))
 if xx1<xx0 or yy1<yy0:continue
 yy,xx=np.mgrid[yy0:yy1+1,xx0:xx1+1];v=np.stack((xx+.5,yy+.5),-1)-tri[0];a,b=tri[1]-tri[0],tri[2]-tri[0];det=a[0]*b[1]-a[1]*b[0]
 if abs(det)<1e-9:continue
 u=(v[...,0]*b[1]-v[...,1]*b[0])/det;t=(a[0]*v[...,1]-a[1]*v[...,0])/det;inside=(u>=0)&(t>=0)&(u+t<=1);sl=np.s_[yy0:yy1+1,xx0:xx1+1]
 if stem_faces[index]:stem_uv[sl]=np.maximum(stem_uv[sl],inside)
 if skin_faces[index]:skin[sl]=np.maximum(skin[sl],inside)
 forced_pixels=np.zeros(inside.shape,bool)
 if force_candidates[index] or feature_faces[index]:
  positions=wtri[index,0]+u[...,None]*(wtri[index,1]-wtri[index,0])+t[...,None]*(wtri[index,2]-wtri[index,0]);p=project(positions)
  if force_candidates[index]:
   for polygon in cfg.get('facePolygons',[]):forced_pixels|=inside_polygon(p.reshape(-1,2),polygon).reshape(inside.shape)&inside
   skin[sl]=np.maximum(skin[sl],forced_pixels)
 if not skin_faces[index] and not feature_faces[index]:protected[sl]|=inside&~forced_pixels
 if not feature_faces[index]:continue
 c=np.zeros(inside.shape,np.float32);e=np.zeros_like(c)
 for cx,cy,rx,ry in cfg['eyes']:
  distance=np.sqrt(((p[...,0]-cx)/rx)**2+((p[...,1]-cy)/ry)**2);e=np.maximum(e,np.clip((1-distance)*min(rx,ry)/cfg.get('eyeFeather',1)+.5,0,1));c=np.maximum(c,np.clip(24-np.sqrt((p[...,0]-cx)**2+(p[...,1]-cy)**2),0,1))
 distance=np.full(inside.shape,1e6)
 for a,b in zip(curve,curve[1:]):
  a=np.asarray(a);b=np.asarray(b);v=b-a;t2=np.clip(((p-a)*v).sum(-1)/(v*v).sum(),0,1);distance=np.minimum(distance,np.linalg.norm(p-a-t2[...,None]*v,axis=-1))
 pigment=rgb.reshape(H,W,3)[sl]
 # Keep the authored mouth silhouette, which follows the raised mouth mesh,
 # while rebuilding its surrounding skin and removing colored contamination.
 mouth_roi=((p[...,0]-mx)/((x1m-x0m)/2+9))**2+((p[...,1]-my)/(depth+13))**2<1
 smile_mask=(np.clip(stroke+.5-distance,0,1) if cfg.get('helmet') else mouth_roi&(pigment[...,1]<.65)&(pigment[...,0]<.50))
 # Clear a narrow halo around the smile, away from eyes, goggles and hood seams.
 c=np.maximum(c,np.clip(stroke+(15 if cfg.get('helmet') else 8)-distance,0,1))
 coverage[sl]+=inside;clear[sl]=np.maximum(clear[sl],c*inside);pupil[sl]+=e*inside;smile[sl]+=smile_mask*inside
pupil/=np.maximum(coverage,1);smile/=np.maximum(coverage,1)
# Small isolated UV islands need matching feature padding at their seams.
# Padding goes into unrepresented UV texels, never into a covered skin texel.
for mask in (pupil,smile):
 values=np.zeros_like(mask);count=np.zeros_like(mask)
 for dy,dx in [(-1,0),(1,0),(0,-1),(0,1)]:
  valid=np.roll(np.roll(coverage>0,dy,0),dx,1);values+=np.roll(np.roll(mask,dy,0),dx,1)*valid;count+=valid
 fill=(coverage==0)&(count>0)&~protected;mask[fill]=values[fill]/count[fill]
 clear=np.maximum(clear,mask)
# Skin-only UV padding avoids seam cracks while protecting adjacent fabric.
original_green=((rgb[:,1]>rgb[:,0]*ratio)&(rgb[:,1]>rgb[:,2]*blue_ratio)&(rgb[:,1]>.20)).reshape(H,W)
padded=skin.copy()
for dy in range(-3,4):
 for dx in range(-3,4):padded=np.maximum(padded,np.roll(np.roll(skin,dy,0),dx,1))
skin=np.maximum(skin,padded*(~protected));skin=np.maximum(skin,clear)
for mask in (skin,clear,pupil,smile,stem_uv):mask[protected]=0
for label,data in [('skin',skin),('clear',clear),('pupil',pupil),('smile',smile),('stem',stem_uv)]:np.save(root/(label+'-mask.npy'),data)
assert (pupil>.99).sum()>25 and (smile>.99).sum()>10

def mask_node(nodes,data,label):
 image=bpy.data.images.new(label,width=W,height=H,alpha=False);image.colorspace_settings.name='Non-Color';rgba=np.ones((H,W,4),np.float32);rgba[:,:,:3]=data[:,:,None];image.pixels.foreach_set(rgba.ravel());node=nodes.new('ShaderNodeTexImage');node.image=image;node.interpolation='Closest';return node

def bake(old,dest,value=None):
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.mesh.primitive_plane_add(size=2);mat=bpy.data.materials.new('Protected skin repair');mat.use_nodes=True;bpy.context.object.data.materials.append(mat);n,l=mat.node_tree.nodes,mat.node_tree.links;n.clear()
 tex=n.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(old));tex.image.colorspace_settings.name='sRGB' if value is None else 'Non-Color'
 if W>1024:tex.interpolation='Closest'
 def mix(base,mask,rgb=None,other=None):
  m=n.new('ShaderNodeMixRGB');l.new(mask_node(n,mask,'Region').outputs[0],m.inputs[0]);l.new(base,m.inputs[1])
  if other is not None:l.new(other,m.inputs[2])
  else:m.inputs[2].default_value=(*rgb,1)
  return m.outputs[0]
 if value is None:
  sep=n.new('ShaderNodeSeparateColor');l.new(tex.outputs['Color'],sep.inputs['Color']);ramp=n.new('ShaderNodeValToRGB');ramp.color_ramp.interpolation='LINEAR';ramp.color_ramp.elements[0].position=float(linear(.50));ramp.color_ramp.elements[0].color=(*linear(np.array([55,108,60])/255),1);ramp.color_ramp.elements[1].position=float(linear(.70));ramp.color_ramp.elements[1].color=(*linear(np.array([151,211,106])/255),1);l.new(sep.outputs['Green'],ramp.inputs[0])
  base=n.new('ShaderNodeRGB');base.outputs[0].default_value=(*linear(np.array([151,211,106])/255),1)
  palette=mix(base.outputs[0],(np.ones((H,W)) if cfg.get('helmet') or name=='scientist' else green_mask(rgb).reshape(H,W)),other=ramp.outputs[0]);final=mix(tex.outputs[0],skin,other=palette);final=mix(final,stem_uv,linear(np.array([55,108,60])/255));final=mix(final,clear,linear(np.array([151,211,106])/255));final=mix(final,pupil,linear(np.array([12,12,12])/255));final=mix(final,smile,linear(np.array([32,69,42])/255))
 else:final=mix(tex.outputs[0],skin,value)
 emission=n.new('ShaderNodeEmission');l.new(final,emission.inputs['Color']);out=n.new('ShaderNodeOutputMaterial');l.new(emission.outputs[0],out.inputs['Surface']);target_size=W if value is None else 1024;image=bpy.data.images.new('Clean channel',width=target_size,height=target_size,alpha=False);image.colorspace_settings.name='sRGB' if value is None else 'Non-Color';target=n.new('ShaderNodeTexImage');target.image=image;n.active=target;scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=1;scene.render.bake.margin=0;bpy.ops.object.bake(type='EMIT');image.filepath_raw=str(dest);image.file_format='PNG';image.save()
mapping={}
for channel,value in [('diffuseColor',None),('normal',(.5,.5,1)),('roughness',(155/255,)*3),('metallic',(0,0,0))]:
 shader,old=channels[channel];new='./textures/unified-skin-'+channel+'.png';bake(work/old.lstrip('./'),work/new.lstrip('./'),value);shader.GetInput('file').Set(Sdf.AssetPath(new));mapping[old]=new
# Average welded geometric normals on skin only. Cat-bear's repaired tail and
# restored rear fabric are separate meshes and remain byte-value identical.
_,weld=np.unique(np.round(pts,5),axis=0,return_inverse=True);f=pts[faces];cross=np.cross(f[:,1]-f[:,0],f[:,2]-f[:,0]);sums=np.zeros((weld.max()+1,3))
for j in range(3):np.add.at(sums,weld[faces[:,j]],cross)
sums/=np.maximum(np.linalg.norm(sums,axis=1)[:,None],1e-12)
selected=skin[np.clip((cent[:,1]*H).astype(int),0,H-1),np.clip((cent[:,0]*W).astype(int),0,W-1)]>.5
old=np.asarray(mesh.GetNormalsAttr().Get());assert mesh.GetNormalsInterpolation()=='faceVarying';normals=old.reshape(-1,3,3).copy();normals[selected]=sums[weld[faces[selected]]];mesh.GetNormalsAttr().Set(Vt.Vec3fArray.FromNumpy(normals.reshape(-1,3).astype(np.float32)))
stage.GetRootLayer().Save();compact=work/'compact.usdc';assert stage.GetRootLayer().Export(str(compact));shutil.move(compact,layer)
if output.exists():output.unlink()
assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer)),str(output))
before=Usd.Stage.Open(str(source));after=Usd.Stage.Open(str(output))
for p in before.Traverse():
 q=after.GetPrimAtPath(p.GetPath());assert q and p.GetTypeName()==q.GetTypeName()
 for attr in p.GetAttributes():
  a,b=attr.Get(),q.GetAttribute(attr.GetName()).Get()
  if isinstance(a,Sdf.AssetPath):assert b.path==mapping.get(a.path,a.path)
  elif attr.GetName()=='normals' and p.GetPath()==prim.GetPath():assert np.array_equal(np.asarray(a).reshape(-1,3,3)[~selected],np.asarray(b).reshape(-1,3,3)[~selected])
  else:assert a==b,str(attr.GetPath())
  assert attr.GetConnections()==q.GetAttribute(attr.GetName()).GetConnections()
 for rel in p.GetRelationships():assert rel.GetTargets()==q.GetRelationship(rel.GetName()).GetTargets()
with zipfile.ZipFile(source) as a,zipfile.ZipFile(output) as b:
 assert b.testzip() is None
 for entry in a.namelist()[1:]:
  if entry in b.namelist():assert a.read(entry)==b.read(entry)
 raw=output.read_bytes()
 for entry in b.infolist():
  assert entry.compress_type==zipfile.ZIP_STORED;x,y=struct.unpack_from('<HH',raw,entry.header_offset+26);assert (entry.header_offset+30+x+y)%64==0
bpy.ops.wm.read_factory_settings(use_empty=True);new=pixels(bpy.data.images.load(str(work/'textures/unified-skin-diffuseColor.png')));outside=skin.ravel()==0;error=float(np.abs(rgb[outside]-new[outside]).max());assert error<=1/255+1e-6
assert np.abs(new[pupil.ravel()>.999]-12/255).max()<=1/255+1e-6
report={'id':name,'sourceSHA256':cfg['sourceSHA256'],'outputSHA256':hashlib.sha256(output.read_bytes()).hexdigest(),'bytes':output.stat().st_size,'baseColor':'#97D36A','stripeColor':'#376C3C','eyeColor':'#0C0C0C','mouthColor':'#20452A','roughness':155/255,'metallic':0,'outsideSkinColorMaxError':error,'geometryUVsTransformsBindingsUnchanged':True,'clothingNormalsUnchanged':True,'otherMeshesUnchanged':True,'skinFaces':int(selected.sum()),'pupilPixels':int((pupil>.99).sum()),'colorTextureSize':W,'otherTextureSize':1024}
assert report['bytes']<12*1024*1024
(root/'repair-report.json').write_text(json.dumps(report,indent=2)+'\n');print('REPAIRED',report,flush=True)
