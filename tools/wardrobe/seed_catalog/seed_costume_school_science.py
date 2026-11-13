"""Fit the original school uniform and two laboratory looks to the neutral seed."""
import io
import re
import subprocess
import zipfile

import numpy as np
from PIL import Image

import seed_costume_geometry as geometry
from seed_costume_geometry import arm_sections, as_mesh, load, meshes, sample, smoothstep, unit


def make_school_mask(co, green, rgb, name):
    x, y, z = co.T
    r, g, b = rgb.T
    uniform = (b - r > 9) | (r + g + b < 410) | (r > 202)
    skin_face = green | ((y > .72) & (g - r > 4) & (r-b>7))
    coat_collar = (r > 180) & (g > 180) & (b > 145)
    lower = y < .452
    return lower | ((y < .887) & (~skin_face) & (uniform | coat_collar))


def make_goggles_mask(co, green, rgb, name):
    x, y, z = co.T
    r,g,b = rgb.T
    # All coat and trouser surfaces below the cuff are authored cloth; some areas contain baked green reflections.
    hand=(abs(x)>.251)&(y>.447)&(y<.583)&green
    return ((y < .907) & (~green | ((y<.677)&~hand)))


def make_scientist_mask(co, green, rgb, name):
    x, y, z = co.T
    r,g,b = rgb.T
    pale=(r>151) & (b>100) & (g-r<35)
    neutral=(np.maximum.reduce([r,g,b]) - np.minimum.reduce([r,g,b])<47)
    raised=(x<-.202) & (y>.835)
    flask=(x<-.211) & (y>.939) & (z>.119) & ((pale & (x>-.351)) | (neutral & (y<1.4)))
    hand_area=(x>.253)&(y>.421)&(y<.581)
    right_hand=hand_area&(green | ((g-r>10)&(g>b+14)))
    coat=(y < .962) & (~green) & ~right_hand & ~((y>.865) & ~pale & (z>.100))
    lower = (y<.684)&~right_hand
    # The lanyard and embroidered ink share the coat's original atlas.
    return lower | coat | (raised & ~green & pale & (y<.985)) | flask


def fit_model(p, faces, name, *, mode, body, arms, source):
    x,y,z = p.T.copy()
    coat = smoothstep((y-.252)/.120)
    front = smoothstep((z-.025)/.100)
    if mode in ('school','goggles'):
        lens = smoothstep((y-1.163)/.043) if mode=='goggles' else np.zeros(len(p))
        # Bring the neck opening down a little near the face, preserving the lapels and tie.
        p[:,1] -= .019 * smoothstep((y-.739)/.085) * front * (1-lens)
    else:
        lens = smoothstep((y-1.036)/.032) * smoothstep((x+.229)/.054)
        p[:,1] -= .023 * smoothstep((y-.757)/.127) * front * (1-lens) * smoothstep((x+.255)/.093)

    p[:,0] *= 1.018 + .025*coat
    p[:,2] *= 1.06 + .044*coat
    p[:,2] += .019 + .007*coat
    if mode=='scientist':
        # This version's original face, coat, and shoes are all set rearward.
        # Align the front tailoring and shoe centers with the new rest pose.
        p[:,2] += .066 * (1 - smoothstep((y-.65)/.255))
        p[:,0] += .023 * (1 - smoothstep((y-.355)/.070))
    # Keep narrow ankles aligned with the neutral figure and stretch boots only beneath the hem.
    shoes = 1-smoothstep((y-.071)/.067)
    p[:,0] -= np.sign(x)*(.002 if mode=='scientist' else .025)*shoes
    p[:,2] += .013*shoes
    # Open each cuff over the slightly lower master forearm center, preserving drape at the shoulder.
    for arm in ('LeftArm','RightArm'):
        side=-1 if arm=='LeftArm' else 1
        if mode=='scientist' and side==-1: continue
        cuff = smoothstep((side*x-.229)/.102)*(1-smoothstep((y-.705)/.143))*smoothstep((y-.479)/.073)
        if mode=='scientist':
            cuff = smoothstep((side*x-.226)/.067)*(1-smoothstep((y-.635)/.170))*smoothstep((y-.435)/.046)
        p[:,1] += (.041 if mode=='school' else (.099 if mode=='scientist' else .048))*cuff
        p[:,2] += .029*cuff
        adjusted=p.copy()
        arms[arm].push_out(adjusted,.009)
        # Let the existing hand stay exposed under the sleeve opening.
        cuff_mesh=smoothstep((side*x-.212)/.039)*smoothstep((p[:,1]-.504)/.041)*(1-lens)
        p += (adjusted-p)*cuff_mesh[:,None]
    # Separate original cloth shells before applying the clearance clamp; otherwise
    # the dark trousers, shirt and the light lab coat can meet on the same surface.
    if mode in ('scientist','goggles'):
        # Separate an outer coat from the pants beneath, retaining both original textures.
        source_faces, source_uv, source_tex=source
        colors=sample(source_tex,source_uv.mean(axis=1)).astype(float)
        cloth=(colors.min(axis=1)>149)&(colors.max(axis=1)-colors.min(axis=1)<48)
        weights=np.zeros(len(p)); count=np.zeros(len(p))
        for corner in range(3):
            np.add.at(weights,source_faces[:,corner],cloth)
            np.add.at(count,source_faces[:,corner],1)
        cloth_weight=weights/np.maximum(count,1)
        rear_hem=(1-smoothstep((z+.01)/.050))*smoothstep((y-.27)/.050)*(1-smoothstep((y-.50)/.067))
        separate=(.025*cloth_weight-.016*(1-cloth_weight))*rear_hem
        center=body.sample(p)[0]
        p[:,[0,2]]+=unit(p[:,[0,2]]-center)*separate[:,None]
    # The original seat's inward seam was narrower than the neutral fruit's lower pole.
    # Extend just the inseam downward while leaving the outer trouser silhouette in place.
    saddle=(1-smoothstep((abs(x)-.014)/.095)) * (1-smoothstep((abs(z)-.032)/.081))
    saddle*=smoothstep((y-.195)/.062)*(1-smoothstep((y-.330)/.051))
    p[:,1] -= (.055 if mode in ('goggles','scientist') else .041)*saddle
    torso=smoothstep((y-.264)/.010)*(1-lens)
    if mode=='scientist':
        raised=smoothstep((-x-.206)/.078)*smoothstep((y-.79)/.159)
        p[:,0] -= .026*raised
        p[:,2] += .013*raised
        torso *= 1-raised
    adjusted = p.copy()
    body.push_out(adjusted,.018)
    # Smoothly preserve depth order when easing tight cloth over the body.
    # A hard max clamp pushes unrelated inner and outer shells to the same radius.
    signed_gap=body.clearance(p)
    radial=p[:,[0,2]]-body.sample(p)[0]
    soft=np.zeros(len(p))
    has=np.isfinite(signed_gap)
    need=.013-signed_gap[has]
    soft[has]=.5*(need+np.sqrt(need*need+.023*.023))
    if mode=='school':
        # The trouser saddle sits immediately below the body in the original model.
        # Ease the rear panel around the neutral body's lower pole without reshaping the cuffs.
        rear=(1-smoothstep((z+.065)/.047))*smoothstep((y-.281)/.018)*(1-smoothstep((y-.396)/.046))
        soft += .015*rear
    p[:,[0,2]] += (unit(radial)*(soft*torso)[:,None])
    if mode=='scientist':
        lower_front = (1-smoothstep((abs(x)-.042)/.058)) * smoothstep((z+.012)/.076)
        lower_front *= smoothstep((y-.258)/.045)*(1-smoothstep((y-.378)/.069))
        p[:,2] += .053*lower_front
        # At the distal cuff, use the measured neutral hand volume itself as the envelope.
        collar = smoothstep((x-.220)/.042)*smoothstep((p[:,1]-.51)/.016)*(1-smoothstep((p[:,1]-.658)/.055))
        candidate = p.copy()
        arms['RightArm'].push_out(candidate,.019)
        p += (candidate-p)*collar[:,None]
    if mode != 'school':
        # Preserve smooth easing along the original prop and visor transition.
        if mode == 'goggles':
            p[:, 1] -= .033 * lens
            p[:, 0] *= 1 + .03 * lens
        else:
            p[:, 1] += .012 * lens
            p[:, 0] *= 1 + .08 * lens
        p[:, 2] += .021 * lens
        projected = p.copy()
        body.push_out(projected, .010)
        p += (projected-p)*lens[:,None]
    if mode=='scientist':
        # Remove the final seed-pole overlap across the trouser front. A few
        # triangles span the seam and need more than the vertex radial correction.
        fill=(1-smoothstep((abs(p[:,0])-.04)/.091))*smoothstep((p[:,2]-.029)/.063)
        fill*=smoothstep((p[:,1]-.260)/.039)*(1-smoothstep((p[:,1]-.392)/.052))
        p[:,2] += .048*fill
    p[:,1] = np.maximum(p[:,1],0)
    return p


def author_arm(points):
    # Aim the master forearm up toward the original flask grip. Preserve its wrist and hand sculpt.
    source_shoulder=np.array([-.233,.804,.009])
    source_hand=np.array([-.334,.567,.033])
    target_shoulder=np.array([-.236,.801,.015])
    target_hand=np.array([-.342,.986,.202])
    source = unit(source_hand-source_shoulder)
    target = unit(target_hand-target_shoulder)
    axis=np.cross(source,target)
    sine=np.linalg.norm(axis)
    cosine=source@target
    axis/=sine
    a,b,c=axis
    cross=np.array([[0,-c,b],[c,0,-a],[-b,a,0]])
    rot=np.eye(3)+cross*sine+(cross@cross)*(1-cosine)
    stretch=1+(np.linalg.norm(target_hand-target_shoulder)/np.linalg.norm(source_hand-source_shoulder)-1)
    local=points-source_shoulder
    local += (stretch-1)*(local@source)[:,None]*source
    return target_shoulder+local@rot.T


def shell_faces(n, rings):
    return np.asarray([tri for i in range(rings-1) for j in range(n)
                       for tri in [(i*n+j,i*n+(j+1)%n,(i+1)*n+j),
                                   (i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j)]],dtype=int)


def add_eyewear(mode, body):
    # Match the original visor outlines but keep the lenses transparent to the master face.
    forehead=mode=='goggles'
    y0=1.246 if forehead else 1.156
    half_x=.182 if forehead else .203
    n=96
    th=np.arange(n)*(2*np.pi/n)
    co,si=np.cos(th),np.sin(th)
    outline_x=half_x*np.sign(co)*abs(co)**.61
    outline_y=(.055 if forehead else .066)*np.sign(si)*abs(si)**.65
    notch=np.exp(-((outline_x/(.040 if forehead else .037))**2))*(si<0)
    outline_y+=notch*(.031 if forehead else .029)
    outline_y += (.017 if forehead else -.003) * (outline_x/half_x)**2

    def panel(scale=1.,depth=0.):
        x=outline_x*scale; y=y0+outline_y*scale
        front=(.199 if forehead else .235)-(.081 if forehead else .086)*(abs(x)/half_x)**1.74
        return np.column_stack([x,y,front+depth])

    # A thin rounded rubber bezel wraps the edge of the single polycarbonate lens.
    outer=panel(1.03)
    inner=panel(.88,.003)
    for ring in (outer,inner):
        # Back-of-frame distance stays positive even at the original green stripe peaks.
        raised=ring.copy()
        body.push_out(raised,.014)
        ring[:] = raised
    bezel=np.concatenate([outer-[0,0,.005],outer+[0,0,.005],inner,inner-[0,0,.006],outer-[0,0,.005]])
    frame=shell_faces(n,5)
    central=inner.mean(axis=0)+[0,0,.047 if forehead else .051]
    lens=np.concatenate([inner, central[None,:]])
    pane=np.asarray([(n,j,(j+1)%n) for j in range(n)])
    # Existing source headband wraps behind the sides of the visor.
    angle=np.linspace(.89,2*np.pi-.89,128)
    direction=np.column_stack([np.sin(angle),np.cos(angle)])
    wrap=[]
    for offset,delta in ((-.016,0),(.016,0),(.016,.008),(-.016,.008),(-.016,0)):
        ys=y0+offset-(.025 if forehead else .012)*(1-np.cos(angle))/2
        ps=np.column_stack([direction[:,0],ys,direction[:,1]])
        center,vector,radius=body.sample(ps)
        fitted=center+unit(vector)*(radius+.010+delta)[:,None]
        wrap.extend(np.column_stack([fitted[:,0],ys,fitted[:,1]]))
    wrap=np.asarray(wrap)
    bandfaces=[]
    for ring in range(4):
        for i in range(127):
            a=ring*128+i
            bandfaces.extend([(a,a+128,a+1),(a+1,a+128,a+129)])
    # Fasten both ends to the outer corners of the frame.
    for s in (-1,1):
        ix=0 if s==1 else 127
        end=wrap[128+ix:128+ix+1].mean(axis=0)
        center=np.array([s*(half_x-.006),y0+(.017 if forehead else -.004),(.199 if forehead else .235)-(.079 if forehead else .086)])
        x0,x1=sorted([end[0],center[0]])
        lo,hi=sorted([end[2],center[2]])
        xp=len(wrap)
        wrap=np.vstack([wrap,[[x,y,z] for x in [x0-.008,x1+.008] for y in [y0-.015,y0+.020] for z in [lo-.007,hi+.008]]])
        for a,b,c,d in [(0,1,3,2),(4,6,7,5),(0,2,6,4),(1,5,7,3),(0,4,5,1),(2,3,7,6)]:
            bandfaces.extend([(xp+a,xp+b,xp+c),(xp+a,xp+c,xp+d)])
    return [
        ('VisorFrame',bezel,frame, 'VisorFrameMaterial'),
        ('VisorLens',lens,pane,'VisorLensMaterial'),
        ('VisorStrap',wrap,np.asarray(bandfaces), 'VisorStrapMaterial'),
    ]


def material_surface(name,color,roughness,opacity=1.):
    return f'''        def Material "{name}"
        {{
            token outputs:surface.connect = </SeedCostume/Materials/{name}/Surface.outputs:surface>
            def Shader "Surface"
            {{
                uniform token info:id = "UsdPreviewSurface"
                color3f inputs:diffuseColor = {color}
                float inputs:roughness = {roughness}
                float inputs:opacity = {opacity}
                float inputs:metallic = 0
                float inputs:ior = 1.46
                token outputs:surface
            }}
        }}
'''


def add_accessories(id, output, mode, body, arm_data):
    basename=f'seed-costume-{id}'
    path=output/f'{basename}.usda'
    stage=path.read_text()
    material=''; text=''
    if mode=='scientist':
        arm_text=geometry.read_stage(geometry.assets/'Characters'/'SeedCucumberMaster.usdz')
        material=re.search(r'(?ms)^        def Material "LeftArm"\n.*?^        }',arm_text)[0]
        material=material.replace('/Cucumber/Materials/LeftArm','/SeedCostume/Materials/PosedLeftArmMaterial')
        material=material.replace('def Material "LeftArm"','def Material "PosedLeftArmMaterial"')
        material=re.sub(r'@(?:[^@]*\[)?(?:\./)?Textures/LeftArm\.png(?:\])?@', '@textures/MasterLeftArm.png@', material)
        p, f, uv=arm_data['LeftArm']
        pose=author_arm(p)
        text=as_mesh('PosedLeftArm',pose,f,uv).replace('/SeedCostume/Materials/mat0','/SeedCostume/Materials/PosedLeftArmMaterial')
        with zipfile.ZipFile(geometry.assets/'Characters/SeedCucumberMaster.usdz') as source:
            (output/'textures/MasterLeftArm.png').write_bytes(source.read('Textures/LeftArm.png'))
    if mode in ('scientist','goggles'):
        for name,p,f,mat in add_eyewear(mode, body):
            text+=as_mesh(name,p,f,np.zeros((len(f),3,2))).replace('/SeedCostume/Materials/mat0','/SeedCostume/Materials/'+mat)
        material+='\n'+material_surface('VisorFrameMaterial','(0.68, 0.72, 0.66)' if mode=='scientist' else '(0.29, 0.32, 0.30)',.37)
        material+=material_surface('VisorLensMaterial','(0.69, 0.82, 0.74)',.19,.19)
        material+=material_surface('VisorStrapMaterial','(0.055, 0.062, 0.06)',.8)
    stage=stage.replace('    def Scope "Materials"',text+'    def Scope "Materials"',1)
    marker='    def Scope "Materials"\n    {\n'
    stage=stage.replace(marker,marker+material+'\n',1)
    path.write_text(stage)
    (output/f'{basename}.usdz').unlink()
    textures=[str(p.relative_to(output)) for p in (output/'textures').glob('*') if p.is_file()]
    for command in [
        ['/usr/bin/usdcat','-o',f'{basename}.usdc',f'{basename}.usda'],
        ['/usr/bin/usdzip',f'{basename}.usdz',f'{basename}.usdc',*textures],
        ['/usr/bin/usdchecker','--strict','--arkit',f'{basename}.usdz'],
    ]: subprocess.run(command,cwd=output,check=True,timeout=25)


def review(id, output, hidden):
    basename=f'seed-costume-{id}'
    stage=(output/f'{basename}.usda').read_text()
    parts=list(meshes(stage))
    _,texture=load(id)
    textures = [([part for part in parts if part[0] == 'mesh1'],texture)]
    for key,color in [('VisorFrame',[168,174,157] if id=='scientist' else [90,97,90]),('VisorStrap',[52,55,52])]:
        selected=[part for part in parts if part[0]==key]
        if selected: textures.append((selected,np.full((4,4,3),color,dtype=np.uint8)))
    skin = geometry.assets/'Characters/SeedCucumberMaster.usdz'
    with zipfile.ZipFile(skin) as package:
        if id == 'scientist':
            textures.append(([part for part in parts if part[0]=='PosedLeftArm'],
                       np.asarray(Image.open(io.BytesIO(package.read('Textures/LeftArm.png'))).convert('RGB'))))
        for part in geometry.seed_data:
            name=part[0]
            if name in hidden: continue
            suffix='BodyBaseColor' if name=='Body' else name
            image=np.asarray(Image.open(io.BytesIO(package.read(f'Textures/{suffix}.png'))).convert('RGB'))
            textures.append(([part],image))
    geometry.raster(None,textures,id+'-fit')


VARIANTS = {
    'school-uniform-trousers': ('school', make_school_mask, ()),
    'scientist-goggles': ('goggles', make_goggles_mask, ()),
    'scientist': ('scientist', make_scientist_mask, ('LeftArm',)),
}


def prepare(id, output, preview=False):
    mode, mask, hidden = VARIANTS[id]
    body = geometry.body
    arm_data = {name: (p, f, uv) for name, p, f, uv in geometry.seed_data
                if name in ('LeftArm', 'RightArm')}
    arms = {name: arm_sections(p, f) for name, (p, f, _) in arm_data.items()}
    source_text, source_texture = load(id)
    _, _, source_faces, source_uv = next(meshes(source_text))
    source = (source_faces, source_uv, source_texture)
    geometry.prepare(
        id, output, mask,
        lambda p, f, name: fit_model(p, f, name, mode=mode, body=body, arms=arms, source=source),
        hidden=hidden, render=False,
    )
    add_accessories(id, output, mode, body, arm_data)
    if preview:
        review(id, output, tuple(set(hidden) | {'LeftLeg', 'RightLeg'}))
