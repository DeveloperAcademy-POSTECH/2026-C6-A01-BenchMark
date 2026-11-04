"""Generate texture-free front/back UV garment copies from the exact fitted wardrobe meshes.
Original assemblies, points, topology and normals stay unchanged. Run in Blender's Python.
"""
from pathlib import Path
from pxr import Usd, UsdGeom, UsdShade, Sdf, Gf, Vt, UsdUtils
import json, tempfile, hashlib, sys
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'apps/ios/OiDonation/Resources/WardrobePhotoUV'
REPORT=Path(sys.argv[sys.argv.index('--')+1])
OUT.mkdir(exist_ok=True,parents=True); REPORT.mkdir(exist_ok=True,parents=True)
records=[]
def visibility(points, faces, resolution=384):
    xy=points[:,:2]; lo=xy.min(axis=0); span=np.maximum(xy.max(axis=0)-lo,1e-6)
    projected=(xy-lo)/span*(resolution-2)+.5
    zfront=np.full((resolution,resolution),-np.inf); zback=-zfront
    front=np.full((resolution,resolution),-1,dtype=np.int32); back=front.copy()
    for fi,ids in enumerate(faces):
        a,b,c=projected[ids]; zs=points[ids,2]
        xmin,ymin=np.maximum(np.floor(np.min([a,b,c],axis=0)).astype(int),0)
        xmax,ymax=np.minimum(np.ceil(np.max([a,b,c],axis=0)).astype(int),resolution-1)
        yy,xx=np.mgrid[ymin:ymax+1,xmin:xmax+1]; x=xx+.5; y=yy+.5
        det=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(det)<1e-10: continue
        u=((b[1]-c[1])*(x-c[0])+(c[0]-b[0])*(y-c[1]))/det
        v=((c[1]-a[1])*(x-c[0])+(a[0]-c[0])*(y-c[1]))/det
        valid=(u>=-1e-6)&(v>=-1e-6)&(u+v<=1+1e-6)
        depth=u*zs[0]+v*zs[1]+(1-u-v)*zs[2]
        f=valid&(depth>zfront[yy,xx]); zfront[yy[f],xx[f]]=depth[f]; front[yy[f],xx[f]]=fi
        bmask=valid&(depth<zback[yy,xx]); zback[yy[bmask],xx[bmask]]=depth[bmask]; back[yy[bmask],xx[bmask]]=fi
    return front,back


for source,role in [(p,role) for p in sorted((ROOT/'apps/ios/OiDonation/Resources/Wardrobe').glob('*.usdz')) for role in ['Top','Bottom'] if not (role=='Top' and 'postech' in p.name)]:
    name='photo-'+source.stem+'-'+role.lower()
    original_hash=hashlib.sha256(source.read_bytes()).hexdigest()
    stage=Usd.Stage.Open(str(source))
    meshes=[UsdGeom.Mesh(p) for p in stage.Traverse() if p.IsA(UsdGeom.Mesh) and '/'+role+'/' in str(p.GetPath())]
    assert len(meshes)==1,(source,role,len(meshes))
    mesh=meshes[0]
    matrix=UsdGeom.XformCache().GetLocalToWorldTransform(mesh.GetPrim())
    pts=[matrix.Transform(Gf.Vec3d(p)) for p in mesh.GetPointsAttr().Get()]
    points=np.array(pts); counts=list(mesh.GetFaceVertexCountsAttr().Get()); indices=list(mesh.GetFaceVertexIndicesAttr().Get())
    faces=[]; triangles=[]; triangle_faces=[]; cursor=0
    for fi,count in enumerate(counts):
        ids=indices[cursor:cursor+count];cursor+=count;faces.append(ids)
        for j in range(1,count-1):
            triangles.append([ids[0],ids[j],ids[j+1]]);triangle_faces.append(fi)
    front,back=visibility(points,np.array(triangles), resolution=256)
    tf=np.array(triangle_faces)
    front[front>=0]=tf[front[front>=0]]; back[back>=0]=tf[back[back>=0]]
    fv=np.bincount(front[front>=0],minlength=len(faces)); bv=np.bincount(back[back>=0],minlength=len(faces))
    centers=np.array([points[ids].mean(axis=0) for ids in faces])
    # For occluded inner folds, use a smooth local front/back mid-depth, not face direction.
    lo=points.min(axis=0); hi=points.max(axis=0); span=hi-lo
    cells=np.clip(((points[:,:2]-lo[:2])/span[:2]*23).astype(int),0,23)
    local=[]
    for c in centers:
        cell=np.clip(((c[:2]-lo[:2])/span[:2]*23).astype(int),0,23)
        near=points[(abs(cells[:,0]-cell[0])<=1)&(abs(cells[:,1]-cell[1])<=1),2]
        mid=(near.min()+near.max())/2 if len(near) else (lo[2]+hi[2])/2
        local.append(0 if c[2]>=mid else 1)
    groups=np.array(local)
    groups[fv>bv]=0; groups[bv>fv]=1
    scale=.90/max(span[0],span[1])
    uv_values=[]; uv_indices=[]; uv_lookup={}; polygons=[[],[]]; edge_owners={}
    for ids,g in zip(faces,groups):
        g=int(g); poly=[]
        for vi in ids:
            vi=int(vi); p=points[vi]
            u=.5+(p[0]-(lo[0]+hi[0])/2)*scale*(1 if g==0 else -1)
            v=.5-(p[1]-(lo[1]+hi[1])/2)*scale
            key=(vi,g)
            if key not in uv_lookup:
                uv_lookup[key]=len(uv_values); uv_values.append(Gf.Vec2f((g+u)/2,1-v))
            uv_indices.append(uv_lookup[key]); poly.append([round(float(u),6),round(float(v),6)])
        polygons[g].append(poly)
        for j in range(len(ids)):
            key=tuple(sorted((int(ids[j]),int(ids[(j+1)%len(ids)]))))
            edge_owners.setdefault(key,[]).append((g,poly[j],poly[(j+1)%3]))
    edges=[[],[]]
    for owners in edge_owners.values():
        if len(owners)==1 or len(set(o[0] for o in owners))>1:
            for g,a,b in owners: edges[g].append([a,b])
    with tempfile.TemporaryDirectory(prefix='oi-photo-uv-v2-') as temp:
        dest=Path(temp)/'photo.usdc'; out=Usd.Stage.CreateNew(str(dest))
        root=UsdGeom.Xform.Define(out,'/Photo'); out.SetDefaultPrim(root.GetPrim())
        UsdGeom.SetStageUpAxis(out,UsdGeom.Tokens.y); UsdGeom.SetStageMetersPerUnit(out,1)
        m=UsdGeom.Mesh.Define(out,'/Photo/Garment')
        m.CreatePointsAttr(Vt.Vec3fArray([Gf.Vec3f(p) for p in pts]))
        m.CreateFaceVertexCountsAttr(counts);m.CreateFaceVertexIndicesAttr(indices)
        m.CreateSubdivisionSchemeAttr('none');m.CreateDoubleSidedAttr(True)
        original_normals=mesh.GetNormalsAttr().Get()
        if original_normals:
            m.CreateNormalsAttr(Vt.Vec3fArray([Gf.Vec3f(matrix.TransformDir(Gf.Vec3d(n))) for n in original_normals]))
            m.SetNormalsInterpolation(mesh.GetNormalsInterpolation())
        uv=UsdGeom.PrimvarsAPI(m).CreatePrimvar('st',Sdf.ValueTypeNames.TexCoord2fArray,'faceVarying')
        uv.Set(Vt.Vec2fArray(uv_values));uv.SetIndices(Vt.IntArray(uv_indices))
        material=UsdShade.Material.Define(out,'/Photo/White')
        shader=UsdShade.Shader.Define(out,'/Photo/White/Surface');shader.CreateIdAttr('UsdPreviewSurface')
        shader.CreateInput('diffuseColor',Sdf.ValueTypeNames.Color3f).Set((1,1,1))
        shader.CreateInput('roughness',Sdf.ValueTypeNames.Float).Set(.9)
        material.CreateSurfaceOutput().ConnectToSource(shader.ConnectableAPI(),'surface')
        UsdShade.MaterialBindingAPI.Apply(m.GetPrim()).Bind(material);out.GetRootLayer().Save()
        result=OUT/(name+'.usdz')
        if result.exists():result.unlink()
        assert UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(str(dest)),str(result))
        verify=Usd.Stage.Open(str(result)); vm=UsdGeom.Mesh.Get(verify,'/Photo/Garment')
        assert list(vm.GetFaceVertexIndicesAttr().Get())==indices
        error=max((Gf.Vec3d(a)-b).GetLength() for a,b in zip(vm.GetPointsAttr().Get(),pts));assert error<1e-6
        assert len(UsdGeom.PrimvarsAPI(vm).GetPrimvar('st').ComputeFlattened())==len(indices)
    for g,side in enumerate(['front','back']):
        # Boundary-only guide: no full wireframe or large polygon JSON bundled.
        (OUT/(name+'-'+side+'.json')).write_text(json.dumps(edges[g],separators=(',',':')))
    front_wrong=float(np.mean(groups[front[front>=0]]!=0)); back_wrong=float(np.mean(groups[back[back>=0]]!=1))
    assert front_wrong<.12 and back_wrong<.12,(name,front_wrong,back_wrong)
    assert hashlib.sha256(source.read_bytes()).hexdigest()==original_hash
    records.append({'id':name,'sourceSHA256':original_hash,'faces':len(counts),'maxPositionErrorMeters':error,'frontWrongChartPixelFraction':front_wrong,'backWrongChartPixelFraction':back_wrong,'bytes':result.stat().st_size})
    print('PHOTO_UV_READY',records[-1],flush=True)
(REPORT/'photo-uv-validation.json').write_text(json.dumps(records,indent=2))
