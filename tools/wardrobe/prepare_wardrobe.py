"""Build source-matched, 1.5 m wardrobe variants. Never edits source models.
Run: Blender -b --python prepare_wardrobe.py -- WORKSPACE OUTPUT_DIR REPORT_DIR
"""
import bpy,bmesh,math,json,sys,hashlib
import numpy as np
from pathlib import Path
from mathutils import Vector
args=sys.argv[sys.argv.index('--')+1:]
WORK,OUT,REPORT=map(Path,args)
OUT.mkdir(parents=True,exist_ok=True);REPORT.mkdir(parents=True,exist_ok=True)
TRIAL=WORK/'meshy_output/compatibility-audit-20261101/trial/separated'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
lib={};sources={}
for src in ['base','shorts','hoodie','cardigan','postech']:
    path=TRIAL/f'{src}-parts.blend'
    sources[src]=hashlib.sha256(path.read_bytes()).hexdigest()
    with bpy.data.libraries.load(str(path),link=False) as (a,b):
        b.objects=[n for n in a.objects if n.startswith(src+'__') and not n.endswith('foot_origin')]
    lib[src]={o.get('part_role'):o for o in b.objects if o}
# Keep source UVs and the source atlas. Recoloring is per semantic part at runtime.
for im in bpy.data.images:
    if im.type=='IMAGE':
        if max(im.size)>1024: im.scale(1024,1024)
        im.pack()

def clone(o,name):
    n=o.copy();n.data=o.data.copy();n.name=name;n.parent=None
    n.location=(0,0,0);n.rotation_euler=(0,0,0);n.scale=(1,1,1)
    scene.collection.objects.link(n)
    return n

def boundary_ring(o):
    bm=bmesh.new();bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.00001)
    p=np.array([v.co[:] for v in bm.verts if v.is_boundary and v.co.z>.39]);bm.free()
    # Angular neighborhood of the original waistband, not normals on fabric folds.
    angles=np.arctan2(p[:,1],p[:,0]);out=[]
    for a in np.linspace(-math.pi,math.pi,256,endpoint=False):
        d=np.abs(np.angle(np.exp(1j*(angles-a))))
        candidates=p[d<.06]
        if len(candidates)==0:candidates=p[np.argsort(d)[:5]]
        out.append([np.median(np.linalg.norm(candidates[:,:2],axis=1)),np.median(candidates[:,2])])
    return np.array(out)

def fit_waist(pants,source,target):
    a=boundary_ring(source);b=boundary_ring(target)
    for v in pants.data.vertices:
        if v.co.z<=.33:continue
        theta=math.atan2(v.co.y,v.co.x);idx=int((theta+math.pi)/(2*math.pi)*256)%256
        r,z=a[idx];rt,zt=b[idx]
        w=max(0,min(1,(v.co.z-.33)/max(.02,z-.33)));w=w*w*(3-2*w)
        rr=math.hypot(v.co.x,v.co.y)
        delta=(rt-r-.002)*w
        if rr>.001: v.co.x*=max(.5,(rr+delta)/rr);v.co.y*=max(.5,(rr+delta)/rr)
        v.co.z+=(zt-z)*w
    pants.data.update()

def finish(o,role):
    bm=bmesh.new();bm.from_mesh(o.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000002)
    # Keep original boundary vertices, including the neck, wrist, and hem seams.
    bm.to_mesh(o.data);bm.free()
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
    target={'head':26000,'arm_left':4000,'arm_right':4000,'top':30000,'pants':22000,'shoes':12000,'leg_left':3000,'leg_right':3000}[role]
    if len(o.data.polygons)>target:
        bm=bmesh.new();bm.from_mesh(o.data);bm.verts.ensure_lookup_table()
        boundary=[v.index for v in bm.verts if v.is_boundary]
        bm.free()
        group=o.vertex_groups.new(name='PreserveSeams');group.add(list(range(len(o.data.vertices))),1,'REPLACE')
        if boundary:group.add(boundary,0,'REPLACE')
        mod=o.modifiers.new('Mobile detail','DECIMATE');mod.ratio=target/len(o.data.polygons)
        mod.vertex_group=group.name;mod.vertex_group_factor=1000
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for poly in o.data.polygons:poly.use_smooth=True

def white_shoes(o):
    mat=bpy.data.materials.get('WhiteSneakers')
    if mat is None:
        mat=bpy.data.materials.new('WhiteSneakers');mat.use_nodes=True
        bs=next(n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].default_value=(.82,.82,.80,1);bs.inputs['Roughness'].default_value=.82
    o.data.materials.clear();o.data.materials.append(mat)

scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True
scene.render.resolution_x=480;scene.render.resolution_y=640;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='JPEG';scene.render.image_settings.quality=88
scene.view_settings.view_transform='AgX'
scene.world=bpy.data.worlds.new('Studio');scene.world.use_nodes=True
next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[0].default_value=(.72,.74,.66,1)
next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND').inputs[1].default_value=.65
for name,loc,power,size in [('Key',(-3,-4,4),450,5),('Fill',(3,-1,3),180,4),('Rim',(0,4,3),240,4)]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.size=size
    ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=loc
    ob.rotation_euler=(Vector((0,0,.75))-ob.location).to_track_quat('-Z','Y').to_euler()
c=bpy.data.cameras.new('Camera');cam=bpy.data.objects.new('Camera',c);scene.collection.objects.link(cam);scene.camera=cam
c.type='ORTHO';c.ortho_scale=1.72
records=[]
for top in ['tshirt','hoodie','cardigan','postech']:
 for bottom in ['long','shorts']:
    src=('shorts' if bottom=='shorts' else 'base') if top=='tshirt' else top
    lower='shorts' if bottom=='shorts' else ('base' if top=='postech' else src)
    model_id=f'wardrobe-{top}-{bottom}'
    objects=[]
    for role in ['head','arm_left','arm_right','top']:
        ob=clone(lib[src][role],'Top' if role=='top' else 'Skin_'+role)
        finish(ob,role);objects.append(ob)
    pants=clone(lib[lower]['pants'],'Bottom')
    if lower!=src:fit_waist(pants,lib[lower]['pants'],lib[src]['pants'])
    finish(pants,'pants');objects.append(pants)
    if bottom=='shorts':
        for role in ['leg_left','leg_right']:
            ob=clone(lib['shorts'][role],'Skin_'+role);finish(ob,role);objects.append(ob)
    shoes=clone(lib[lower]['shoes'],'Shoes');finish(shoes,'shoes');white_shoes(shoes);objects.append(shoes)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    dest=OUT/(model_id+'.usdz')
    bpy.ops.wm.usd_export(filepath=str(dest),selected_objects_only=True,export_textures=True,export_materials=True,export_uvmaps=True,export_normals=True,relative_paths=True,root_prim_path='/OiWardrobe',convert_orientation=True,export_animation=False,meters_per_unit=1,export_custom_properties=False)
    points=[v.co for o in objects for v in o.data.vertices]
    height=max(v.z for v in points)-min(v.z for v in points)
    assert abs(height-1.5)<.002,(model_id,height)
    record={'id':model_id,'top':top,'bottom':bottom,'bodySource':src,'bottomSource':lower,'waistAdapted':lower!=src,'heightMeters':height,'bytes':dest.stat().st_size,'triangles':sum(len(o.data.polygons) for o in objects),'sha256':hashlib.sha256(dest.read_bytes()).hexdigest()}
    records.append(record)
    for angle,label in [(0,'front'),(math.pi/2,'left'),(-math.pi/2,'right'),(math.pi,'back')]:
        target=Vector((0,0,.76));cam.location=target+Vector((4*math.sin(angle),-4*math.cos(angle),.10))
        cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(REPORT/(model_id+'-'+label+'.jpg'));bpy.ops.render.render(write_still=True)
    print('WARDROBE_READY',json.dumps(record),flush=True)
    for o in objects:bpy.data.objects.remove(o,do_unlink=True)
(REPORT/'manifest.json').write_text(json.dumps({'sourceHashes':sources,'variants':records},indent=2))
