"""Build separate AR assets from the committed source USDZs using Blender 4.5.
Run with Blender --background --factory-startup --python <this file>.
Override OI_RESOURCES and OI_AR_WORK if needed. Original assets are never written.
"""
import bpy,json,os,zipfile,math
import numpy as np
from pathlib import Path
from pxr import Usd,UsdGeom,UsdUtils,Sdf,Vt,Gf
resources=Path(os.environ.get('OI_RESOURCES',str(Path(__file__).resolve().parents[1]/'OiDonation/Resources')))

def pack_vertices(mesh,prim):
 vi=np.array(mesh.GetFaceVertexIndicesAttr().Get(),dtype=np.int32);points=np.array(mesh.GetPointsAttr().Get(),dtype=np.float32);n=np.array(mesh.GetNormalsAttr().Get(),dtype=np.float32);uvvar=UsdGeom.PrimvarsAPI(prim).GetPrimvar('st');uv=np.array(uvvar.ComputeFlattened(),dtype=np.float32)
 keys=np.column_stack((vi.astype(np.float32),n,uv));unique,idx=np.unique(keys,axis=0,return_inverse=True);idx=idx.astype(np.int32)
 p=points[unique[:,0].astype(np.int32)];n=unique[:,1:4].copy();uv=unique[:,4:6].copy();tri=idx.reshape(-1,3)
 v1=p[tri[:,1]]-p[tri[:,0]];v2=p[tri[:,2]]-p[tri[:,0]];u1=uv[tri[:,1]]-uv[tri[:,0]];u2=uv[tri[:,2]]-uv[tri[:,0]]
 det=u1[:,0]*u2[:,1]-u1[:,1]*u2[:,0];inv=np.divide(1.,det,out=np.zeros_like(det),where=abs(det)>1e-12)
 t=(v1*u2[:,1,None]-v2*u1[:,1,None])*inv[:,None];b=(v2*u1[:,0,None]-v1*u2[:,0,None])*inv[:,None]
 tv=np.zeros_like(p);bv=np.zeros_like(p);np.add.at(tv,idx,np.repeat(t,3,axis=0));np.add.at(bv,idx,np.repeat(b,3,axis=0));tv-=n*np.sum(tv*n,axis=1)[:,None];length=np.linalg.norm(tv,axis=1);tv=np.divide(tv,length[:,None],out=np.zeros_like(tv),where=length[:,None]>1e-8);tv[length<=1e-8]=[1,0,0]
 w=np.where(np.sum(np.cross(n,tv)*bv,axis=1)<0,-1.,1.).astype(np.float32);tangent=np.column_stack((tv,w)).astype(np.float32)
 mesh.GetPointsAttr().Set(Vt.Vec3fArray.FromNumpy(p));mesh.GetFaceVertexIndicesAttr().Set(Vt.IntArray.FromNumpy(idx));mesh.GetNormalsAttr().Set(Vt.Vec3fArray.FromNumpy(n));mesh.SetNormalsInterpolation('vertex');uvvar.Set(Vt.Vec2fArray.FromNumpy(uv));uvvar.SetInterpolation('vertex');prim.RemoveProperty('primvars:st:indices');UsdGeom.PrimvarsAPI(prim).CreatePrimvar('tangents',Sdf.ValueTypeNames.Float4Array,'vertex').Set(Vt.Vec4fArray.FromNumpy(tangent))


root=resources/'Characters';output=resources/'ARModels';output.mkdir(parents=True,exist_ok=True)
work_root=Path(os.environ.get('OI_AR_WORK','/private/tmp/oi-ar-assets'))
work_root.mkdir(parents=True,exist_ok=True)
report=[]
for name,target in [('ponix',200000),('neopjuk',None),('ponixVsNeopjuk',120000)]:
 bpy.ops.wm.read_factory_settings(use_empty=True)
 src=root/(name+'.usdz');work=work_root/name;work.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(src) as z:z.extractall(work)
 layer=next(p for p in work.glob('*.usdc') if p.name!='compact.usdc');stage=Usd.Stage.Open(str(layer));prim=next(p for p in stage.Traverse() if p.IsA(UsdGeom.Mesh));usd=UsdGeom.Mesh(prim)
 before=len(usd.GetFaceVertexCountsAttr().Get());points=np.array(usd.GetPointsAttr().Get(),dtype=np.float32)
 uvattr=UsdGeom.PrimvarsAPI(prim).GetPrimvar('st');oldbounds=[points.min(0).tolist(),points.max(0).tolist()]
 if target:
  bpy.ops.wm.usd_import(filepath=str(src),import_textures_mode='IMPORT_COPY',import_textures_dir=str(work/'preview'))
  obj=next(o for o in bpy.data.objects if o.type=='MESH');data=obj.data
  # Keep original authored USD node transforms, bindings and material networks.
  raw=np.empty(len(data.vertices)*3,dtype=np.float32);data.vertices.foreach_get('co',raw)
  assert len(data.vertices)==len(points) and np.allclose(raw.reshape(-1,3)[:100],points[:100]),'Importer changed local geometry basis'
  bpy.context.view_layer.objects.active=obj;obj.select_set(True)
  m=obj.modifiers.new('ARConservativeReduction','DECIMATE');m.ratio=min(1,target/before);m.use_collapse_triangulate=True
  bpy.ops.object.modifier_apply(modifier=m.name)
  data=obj.data
  coords=np.empty(len(data.vertices)*3,dtype=np.float32);data.vertices.foreach_get('co',coords);coords=coords.reshape(-1,3)
  indices=np.empty(len(data.loops),dtype=np.int32);data.loops.foreach_get('vertex_index',indices)
  counts=np.empty(len(data.polygons),dtype=np.int32);data.polygons.foreach_get('loop_total',counts)
  normals=np.empty(len(data.corner_normals)*3,dtype=np.float32);data.corner_normals.foreach_get('vector',normals)
  uv=np.empty(len(data.loops)*2,dtype=np.float32);data.uv_layers.active.data.foreach_get('uv',uv)
  usd.GetPointsAttr().Set(Vt.Vec3fArray.FromNumpy(coords));usd.GetFaceVertexCountsAttr().Set(Vt.IntArray.FromNumpy(counts));usd.GetFaceVertexIndicesAttr().Set(Vt.IntArray.FromNumpy(indices))
  usd.GetNormalsAttr().Set(Vt.Vec3fArray.FromNumpy(normals.reshape(-1,3)));usd.SetNormalsInterpolation('faceVarying')
  uvattr.Set(Vt.Vec2fArray.FromNumpy(uv.reshape(-1,2)));uvattr.SetInterpolation('faceVarying');prim.RemoveProperty('primvars:st:indices')
  # These vertex-domain buffers describe the old topology; RealityKit regenerates tangents.
  for prop in ['primvars:tangents','primvars:tangents:indices']:
   prim.RemoveProperty(prop)
  usd.GetExtentAttr().Set(Vt.Vec3fArray([Gf.Vec3f(*map(float,coords.min(0))),Gf.Vec3f(*map(float,coords.max(0)))]))
  stage.GetRootLayer().Save()
  after=len(counts);newbounds=[coords.min(0).tolist(),coords.max(0).tolist()]
 else:after=before;newbounds=oldbounds
 # ImageIO via sips keeps normal-map channels and gamma metadata; never alter shader network.
 import subprocess
 texture_report=[]
 for file in work.iterdir():
  if file.suffix.lower() not in ['.png','.jpg','.jpeg']:continue
  limit=512 if any(x in file.name for x in ['metallic','roughness']) else 1024 if file.name=='extracted_image_0.jpg' else 2048
  subprocess.run(['sips','-Z',str(limit),str(file)],check=True,stdout=subprocess.DEVNULL)
  texture_report.append({'file':file.name,'maxDimension':limit})
 dst=output/('ar-'+name+'.usdz')
 if dst.exists():dst.unlink()
 if target: pack_vertices(usd,prim)
 compact=work/'compact.usdc'
 stage.GetRootLayer().Export(str(compact))
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(compact)),str(dst))
 result={'name':name,'trianglesBefore':before,'trianglesAfter':after,'bytesBefore':src.stat().st_size,'bytesAfter':dst.stat().st_size,'boundsBefore':oldbounds,'boundsAfter':newbounds,'textures':texture_report}
 report.append(result);print('OPTIMIZED',json.dumps(result),flush=True)
(work_root/'mascot-manifest.json').write_text(json.dumps(report,indent=2)+'\n')

# Clothing presets retain their geometry and material graphs.
report=[]
for name in ['dinosaur','cat','baseball','farmer','sportswear']:
 src=resources/'Wardrobe'/('wardrobe-costume-'+name+'.usdz');work=work_root/('oi-'+name);work.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(src) as z:z.extractall(work)
 layer=next(work.glob('*.usd*'));stage=Usd.Stage.Open(str(layer));textures=[]
 for file in work.rglob('*'):
  if file.suffix.lower() not in ['.jpg','.png','.jpeg']:continue
  limit=512 if any(v in file.name.lower() for v in ['metallic','roughness']) else 1024 if 'normal' in file.name.lower() else 2048
  before=subprocess.check_output(['sips','-g','pixelWidth','-g','pixelHeight',str(file)],text=True)
  subprocess.run(['sips','-Z',str(limit),str(file)],check=True,stdout=subprocess.DEVNULL)
  textures.append({'name':file.name,'limit':limit,'before':before.strip()})
 dst=output/('ar-oi-'+name+'.usdz')
 if dst.exists():dst.unlink()
 assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(layer)),str(dst))
 faces=sum(sum(c-2 for c in UsdGeom.Mesh(p).GetFaceVertexCountsAttr().Get()) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh))
 report.append({'name':'oi-'+name,'trianglesBefore':faces,'trianglesAfter':faces,'bytesBefore':src.stat().st_size,'bytesAfter':dst.stat().st_size,'textures':textures})
 print(name,src.stat().st_size,dst.stat().st_size,flush=True)
(work_root/'wardrobe-manifest.json').write_text(json.dumps(report,indent=2)+'\n')
