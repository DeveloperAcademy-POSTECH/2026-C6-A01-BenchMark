"""Build small print surfaces for complete costumes without touching their original materials.
Blender -b --python tools/wardrobe/prepare_costume_photo_uv.py -- REPORT [COSTUME_ID ...]
Regions are authored in meters (Y-up, feet at 0, character height 1.5m).
Only the body of the clothing is printable: face, hands, shoes and handheld props are excluded.
Review front/back overlays whenever a source model is replaced; do not reuse stale regions.
"""
from pathlib import Path
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, Vt, UsdUtils
import numpy as np
import json, hashlib, tempfile, sys
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'apps/ios/OiDonation/Resources/WardrobePhotoUV'
REPORT=Path(sys.argv[sys.argv.index('--')+1]);REPORT.mkdir(parents=True,exist_ok=True)
selectedIDs=set(sys.argv[sys.argv.index('--')+2:])
# xmin,xmax,ymin,ymax. Conservative body regions keep accessories and skin intact.
REGIONS={
 'dinosaur':(-.20,.20,.32,.72), 'raincoat':(-.22,.22,.34,.75),
 'bee':(-.22,.22,.40,.63), 'cat':(-.20,.20,.32,.72),
 'astronaut':(-.18,.18,.38,.75), 'scientist':(-.18,.18,.38,.77),
 'cat-bear':(-.19,.02,.32,.72), 'postech-selfie':(-.18,.18,.53,.78),
 'baseball':(-.16,.05,.43,.65), 'cowboy':(-.18,.18,.43,.67),
 'farmer':(-.18,.18,.35,.65), 'sportswear':(-.18,.18,.43,.65),
 'martial-arts':(-.18,.18,.35,.66), 'school-uniform':(-.18,.18,.43,.65),
 'school-uniform-trousers':(-.18,.18,.43,.65),
 'astronaut-navy':(-.18,.18,.38,.75), 'scientist-goggles':(-.18,.18,.38,.70)
}
BACK_OVERRIDES={'cat-bear':(-.19,.19,.32,.72),'baseball':(-.18,.18,.43,.65)}
records=[]
sources=[(ROOT/'apps/ios/OiDonation/Resources/Wardrobe'/('wardrobe-costume-'+k+'.usdz'), k) for k in REGIONS]
sources += [(ROOT/'apps/ios/OiDonation/Resources/Wardrobe'/('wardrobe-postech-'+b+'.usdz'),'postech-modular') for b in ['long','shorts']]
for source,key in sources:
 if selectedIDs and key not in selectedIDs:continue
 before=hashlib.sha256(source.read_bytes()).hexdigest();stage=Usd.Stage.Open(str(source))
 cache=UsdGeom.XformCache(); points=[]; triangles=[]
 for prim in stage.Traverse():
  if not prim.IsA(UsdGeom.Mesh):continue
  if key=='cat-bear' and '/CenteredTail' in str(prim.GetPath()):continue
  if key=='postech-modular' and '/Top/' not in str(prim.GetPath()):continue
  m=UsdGeom.Mesh(prim);matrix=cache.GetLocalToWorldTransform(prim)
  base=len(points);points.extend([tuple(matrix.Transform(Gf.Vec3d(p))) for p in m.GetPointsAttr().Get()])
  counts=m.GetFaceVertexCountsAttr().Get();ids=m.GetFaceVertexIndicesAttr().Get();cursor=0
  reverse=m.GetOrientationAttr().Get()==UsdGeom.Tokens.leftHanded
  for count in counts:
   face=list(ids[cursor:cursor+count]);cursor+=count
   for j in range(1,count-1):
    tri=[base+face[0],base+face[j],base+face[j+1]]
    triangles.append(tri[::-1] if reverse else tri)
 points=np.array(points);triangles=np.array(triangles);verts=points[triangles]
 normals=np.cross(verts[:,1]-verts[:,0],verts[:,2]-verts[:,0]);normals/=np.maximum(np.linalg.norm(normals,axis=1,keepdims=True),1e-10)
 # Smooth offset normals prevent cracks between neighboring triangles.
 vn=np.zeros_like(points)
 for c in range(3):np.add.at(vn,triangles[:,c],normals)
 vn/=np.maximum(np.linalg.norm(vn,axis=1,keepdims=True),1e-10)
 front=REGIONS.get(key,(-.18,.18,.55,.78));back=BACK_OVERRIDES.get(key,front)
 output_points=[];output_normals=[];uvs=[];counts=[];indices=[];lookup={};edges=[[],[]];face_counts=[]
 for face,region in enumerate([front,back]):
  xmin,xmax,ymin,ymax=region;scale=.90/max(xmax-xmin,ymax-ymin)
  inside=((verts[:,:,0]>=xmin)&(verts[:,:,0]<=xmax)&(verts[:,:,1]>=ymin)&(verts[:,:,1]<=ymax)).all(axis=1)
  # Restrict to front/back-facing cloth; preserve sides and original costume underneath.
  inside &= normals[:,2]*(1 if face==0 else -1)>.35
  selected=triangles[inside];assert len(selected)>20,(key,face,len(selected));face_counts.append(len(selected))
  edge_owners={}
  for ids in selected:
   polygon=[]
   for vi in ids:
    point=points[vi];normal=vn[vi]
    u=.5+(point[0]-(xmin+xmax)/2)*scale*(1 if face==0 else -1)
    v=.5-(point[1]-(ymin+ymax)/2)*scale
    key_vertex=(face,int(vi))
    if key_vertex not in lookup:
     lookup[key_vertex]=len(output_points);output_points.append(point+normal*.0015);output_normals.append(normal);uvs.append(Gf.Vec2f((face+u)/2,1-v))
    indices.append(lookup[key_vertex]);polygon.append([round(float(u),5),round(float(v),5)])
   counts.append(3)
   for j in range(3):
    edge=tuple(sorted((int(ids[j]),int(ids[(j+1)%3]))))
    edge_owners.setdefault(edge,[]).append([polygon[j],polygon[(j+1)%3]])
  edges[face]=[e[0] for e in edge_owners.values() if len(e)==1]
 name='photo-'+source.stem+'-top'
 with tempfile.TemporaryDirectory(prefix='oi-costume-print-') as temp:
  dest=Path(temp)/'print.usdc';out=Usd.Stage.CreateNew(str(dest))
  root=UsdGeom.Xform.Define(out,'/Photo');out.SetDefaultPrim(root.GetPrim())
  UsdGeom.SetStageUpAxis(out,'Y');UsdGeom.SetStageMetersPerUnit(out,1)
  m=UsdGeom.Mesh.Define(out,'/Photo/ClothingPrint');m.CreatePointsAttr(Vt.Vec3fArray([Gf.Vec3f(*p) for p in output_points]))
  m.CreateFaceVertexCountsAttr(counts);m.CreateFaceVertexIndicesAttr(indices)
  m.CreateNormalsAttr(Vt.Vec3fArray([Gf.Vec3f(*n) for n in output_normals]));m.SetNormalsInterpolation('vertex')
  m.CreateSubdivisionSchemeAttr('none');m.CreateDoubleSidedAttr(False)
  UsdGeom.PrimvarsAPI(m).CreatePrimvar('st',Sdf.ValueTypeNames.TexCoord2fArray,'vertex').Set(Vt.Vec2fArray(uvs))
  mat=UsdShade.Material.Define(out,'/Photo/Print');shader=UsdShade.Shader.Define(out,'/Photo/Print/Surface');shader.CreateIdAttr('UsdPreviewSurface')
  shader.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set((1,1,1));shader.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.9)
  mat.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(),'surface');UsdShade.MaterialBindingAPI.Apply(m.GetPrim()).Bind(mat)
  out.GetRootLayer().Save();target=OUT/(name+'.usdz')
  if target.exists():target.unlink()
  assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(dest)),str(target))
 for face,label in enumerate(['front','back']):(OUT/(name+'-'+label+'.json')).write_text(json.dumps(edges[face],separators=(',',':')))
 assert hashlib.sha256(source.read_bytes()).hexdigest()==before
 records.append(dict(id=name,sourceSHA256=before,frontRegionMeters=front,backRegionMeters=back,trianglesBySide=face_counts,offsetMeters=.0015,bytes=target.stat().st_size))
 print('PRINT_READY',key,face_counts,flush=True)
manifest=ROOT/'tools/wardrobe/costume-photo-manifest.json'
if selectedIDs and manifest.exists():
 updated={record['id']:record for record in records}
 records=[updated.pop(record['id'],record) for record in json.loads(manifest.read_text())]+list(updated.values())
manifest.write_text(json.dumps(records,indent=2)+'\n')
(REPORT/'manifest.json').write_text(json.dumps(records,indent=2)+'\n')
