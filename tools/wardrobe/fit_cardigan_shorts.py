"""Apply the approved cardigan/shorts fit while preserving textures and other meshes.

Run with Blender 4.5 Python: fit_cardigan_shorts.py -- SOURCE REFERENCE OUTPUT
SOURCE must be the pre-fit cardigan+shorts package; REFERENCE is T-shirt+shorts
with the same original garment atlas. Use a separate output directory.
Apply skin recoloring first, then this fit, then regenerate both PhotoUV overlays.
"""
from pathlib import Path
import argparse,hashlib,json,sys,tempfile,zipfile
import numpy as np
from pxr import Usd,UsdGeom,UsdShade,Sdf,Vt,UsdUtils
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('source',type=Path)
parser.add_argument('reference',type=Path)
parser.add_argument('output',type=Path)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
source=args.source.resolve();reference=args.reference.resolve();OUT=args.output.resolve()
OUT.mkdir(parents=True,exist_ok=True)
target=OUT/'wardrobe-cardigan-shorts.usdz'
assert source!=target and reference!=target, 'Keep the original inputs in a separate directory'
assert not target.exists(), 'Use a new output directory to avoid overwriting an approved result'
scratch=tempfile.TemporaryDirectory(prefix='oi-cardigan-fit-')
work=Path(scratch.name)
with zipfile.ZipFile(source) as z:
 for n in z.namelist(): assert not Path(n).is_absolute() and '..' not in Path(n).parts
 z.extractall(work);root=work/z.namelist()[0]
stage=Usd.Stage.Open(str(root)); original=Usd.Stage.Open(str(source)); ref=Usd.Stage.Open(str(reference));cache=UsdGeom.XformCache()
find=lambda s,role:next(UsdGeom.Mesh(p) for p in s.Traverse() if p.IsA(UsdGeom.Mesh) and '/'+role+'/' in str(p.GetPath()))
bottom=find(stage,'Bottom'); refBottom=find(ref,'Bottom'); top=find(stage,'Top')
assert cache.GetLocalToWorldTransform(bottom.GetPrim())==UsdGeom.XformCache().GetLocalToWorldTransform(refBottom.GetPrim())
def texture_hashes(mesh,archive):
 mat=UsdShade.MaterialBindingAPI(mesh.GetPrim()).ComputeBoundMaterial()[0]
 result=[]
 with zipfile.ZipFile(archive) as z:
  for p in Usd.PrimRange(mat.GetPrim()):
   for a in p.GetAttributes():
    v=a.Get()
    if isinstance(v,Sdf.AssetPath) and v.path: result.append(hashlib.sha256(z.read(v.path.removeprefix('./'))).hexdigest())
 return sorted(result)
assert texture_hashes(bottom,source)==texture_hashes(refBottom,reference),'Reference UV must use the exact same original garment atlas'
geometryNames={'points','normals','extent','faceVertexCounts','faceVertexIndices','primvars:st','primvars:PreserveSeams'}
for name in geometryNames:
 src=refBottom.GetPrim().GetAttribute(name);dst=bottom.GetPrim().GetAttribute(name)
 assert src and dst
 dst.Set(src.Get())
 assert src.GetAllMetadata()==dst.GetAllMetadata(),name
# A slight front-only hem adjustment follows the new, flatter waistband.
def smooth(v,a,b):
 t=np.clip((v-a)/(b-a),0,1);return t*t*(3-2*t)
def offset(p):
 x,y,z=p.T
 return .012*(1-smooth(y,.47,.79))*smooth(z,-.025,.105)*(1-smooth(abs(x),.18,.29))
def deform_mesh(mesh,deform):
 local=np.asarray(mesh.GetPointsAttr().Get(),dtype=np.float64);matrix=np.array(cache.GetLocalToWorldTransform(mesh.GetPrim()));M=matrix[:3,:3]
 world=np.einsum('ni,ij->nj',local,M)+matrix[3,:3];delta=deform(world)
 worldDelta=np.zeros_like(world);worldDelta[:,2]=-delta
 updated=local+np.einsum('ni,ij->nj',worldDelta,np.linalg.inv(M));assert np.isfinite(updated).all()
 mesh.GetPointsAttr().Set(Vt.Vec3fArray.FromNumpy(updated.astype(np.float32)))
 mesh.GetExtentAttr().Set(Vt.Vec3fArray.FromNumpy(np.array([updated.min(0),updated.max(0)],dtype=np.float32)))
 grad=[];eps=1e-5
 for axis in range(3):
  plus=world.copy();minus=world.copy();plus[:,axis]+=eps;minus[:,axis]-=eps
  grad.append((deform(plus)-deform(minus))/(2*eps))
 grad=np.array(grad).T;assert (1-grad[:,2]).min()>.8
 indices=np.asarray(mesh.GetFaceVertexIndicesAttr().Get());assert mesh.GetNormalsInterpolation()=='faceVarying'
 n=np.einsum('ni,ij->nj',np.asarray(mesh.GetNormalsAttr().Get(),dtype=np.float64),np.linalg.inv(M).T)
 g=grad[indices];nz=n[:,2]/(1-g[:,2]);n[:,0]+=g[:,0]*nz;n[:,1]+=g[:,1]*nz;n[:,2]=nz
 n=np.einsum('ni,ij->nj',n,M.T);n/=np.linalg.norm(n,axis=1,keepdims=True);assert np.isfinite(n).all()
 mesh.GetNormalsAttr().Set(Vt.Vec3fArray.FromNumpy(n.astype(np.float32)))
 return float(delta.max())

topRetreat=deform_mesh(top,offset)
def waist_fit(p):
 x,y,z=p.T
 return .008*smooth(y,.39,.45)*smooth(z,-.025,.105)
bottomRetreat=deform_mesh(bottom,waist_fit)
stage.GetRootLayer().Save()
assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(root)),str(target))
after=Usd.Stage.Open(str(target));topPath=top.GetPath();bottomPath=bottom.GetPath()
for p in original.Traverse():
 q=after.GetPrimAtPath(p.GetPath());assert q and p.GetTypeName()==q.GetTypeName()
 for a in p.GetAttributes():
  if (p.GetPath()==topPath and a.GetName() in {'points','normals','extent'}) or (p.GetPath()==bottomPath and a.GetName() in geometryNames):continue
  b=q.GetAttribute(a.GetName());v,w=a.Get(),b.Get()
  assert (v.path==w.path if isinstance(v,Sdf.AssetPath) else v==w),a.GetPath()
  assert a.GetConnections()==b.GetConnections()
 for r in p.GetRelationships():assert r.GetTargets()==q.GetRelationship(r.GetName()).GetTargets()
for name in geometryNames-{'points','normals','extent'}: assert find(after,'Bottom').GetPrim().GetAttribute(name).Get()==refBottom.GetPrim().GetAttribute(name).Get(),name
with zipfile.ZipFile(source) as a,zipfile.ZipFile(target) as b:
 assert a.namelist()==b.namelist() and b.testzip() is None
 for name in a.namelist()[1:]:assert a.read(name)==b.read(name),name
bounds=UsdGeom.BBoxCache(Usd.TimeCode.Default(),['default','render']).ComputeWorldBound(after.GetDefaultPrim()).ComputeAlignedRange();assert abs(bounds.GetSize()[1]-1.5)<.005
def front_bound(mesh):
 m=np.array(UsdGeom.XformCache().GetLocalToWorldTransform(mesh.GetPrim()))
 p=np.einsum('ni,ij->nj',np.asarray(mesh.GetPointsAttr().Get()),m[:3,:3])+m[3,:3]
 return float(p[:,2].max())
report={'sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'outputSHA256':hashlib.sha256(target.read_bytes()).hexdigest(),'shortsTopologyAndUVExactMatchToTshirt':True,'shortsShapeReference':'wardrobe-tshirt-shorts.usdz','waistFrontExtraRetreatMeters':bottomRetreat,'referenceSHA256':hashlib.sha256(reference.read_bytes()).hexdigest(),'cardiganHemMaxRetreatMeters':topRetreat,'shortsFrontBeforeMeters':front_bound(find(original,'Bottom')),'shortsFrontAfterMeters':front_bound(find(after,'Bottom')),'heightMeters':bounds.GetSize()[1],'materialsAndAllTextureBytesUnchanged':True,'headHandsLegsShoesUnchanged':True,'cardiganTopologyAndUVUnchanged':True}
(OUT/'fit-validation.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2),flush=True)

scratch.cleanup()
