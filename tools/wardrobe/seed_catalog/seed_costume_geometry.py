"""Build asset-only costume overlays in the original seed cucumber coordinates."""
from collections.abc import Callable
from pathlib import Path
import io, math, re, struct, subprocess, sys, zipfile
import numpy as np
from PIL import Image, ImageDraw

root: Path
assets: Path

def usd_array(text, name, dtype):
    match = re.search(r"(?m)^\s+\w+\[\] " + re.escape(name) + r" = \[([^\]]*)\]", text)
    if not match:
        raise ValueError(f"Missing array {name}")
    return np.fromstring(match[1].replace("(", "").replace(")", ""), sep=",", dtype=dtype)

def seed_transform(text):
    order = re.search(r'\bxformOpOrder = \[([^\]]*)\]', text)
    result = np.eye(4)
    if order is None:
        return result
    for op in re.findall(r'"([^"]+)"', order[1]):
        name = op.split(":")[1] if ":" in op else op
        match = re.search(r"(?m)^\s+\w+ " + re.escape(op) + r" = (\(.*\))\s*$", text)
        if not match:
            raise ValueError(f"Unsupported or missing USD transform {op}")
        numbers = np.fromstring(match[1].replace("(", "").replace(")", ""), sep=",")
        matrix = np.eye(4)
        if name == "translate" and len(numbers) == 3:
            matrix[3, :3] = numbers
        elif name == "scale" and len(numbers) == 3:
            matrix[:3, :3] = np.diag(numbers)
        elif name == "transform" and len(numbers) == 16:
            matrix = numbers.reshape(4, 4)
        else:
            raise ValueError(f"Unsupported USD transform {op}")
        result = matrix @ result
    return result


def local_transform(attrs):
    angles = re.search(r'xformOp:rotateXYZ = \(([^)]*)\)', attrs)
    if not angles:
        return seed_transform(attrs)
    # USD's authored rotations here only rotate around X. Root translates are zero.
    x,y,z = map(float, angles[1].split(','))
    assert y == z == 0
    c,s = np.cos(np.deg2rad(x)), np.sin(np.deg2rad(x))
    rotate = np.array([[1,0,0,0],[0,c,s,0],[0,-s,c,0],[0,0,0,1]])
    scale = re.search(r'xformOp:scale = \(([^)]*)\)', attrs)
    translate = re.search(r'xformOp:translate = \(([^)]*)\)', attrs)
    if scale: rotate = np.diag([*map(float, scale[1].split(',')),1]) @ rotate
    if translate: rotate[3,:3] = [*map(float, translate[1].split(','))]
    return rotate

prim_pattern = re.compile(r'(?m)^( *)def (Xform|Mesh) "([^"]+)"[^\n]*\n')
next_prim = re.compile(r'(?m)^\s*def \w+ "')
archive = re.compile(r'(?m)asset inputs:file = @([^@]+)@')

def meshes(text):
    ancestors = []
    for prim in prim_pattern.finditer(text):
        indentation, kind, name = prim.groups()
        start = text.index('\n' + indentation + '{', prim.start()) + len(indentation) + 2
        end = text.index('\n' + indentation + '}', start)
        while ancestors and ancestors[-1][0] <= prim.start():
            ancestors.pop()
        block = text[start:end]
        child = next_prim.search(block)
        attrs = block[:child.start()] if child else block
        transform = local_transform(attrs)
        if ancestors: transform = transform @ ancestors[-1][1]
        if kind == 'Xform':
            ancestors.append((end, transform))
            continue
        points = usd_array(attrs, 'points', np.float64).reshape(-1, 3)
        counts = usd_array(attrs, 'faceVertexCounts', np.int32)
        assert np.all(counts == 3)
        faces = usd_array(attrs, 'faceVertexIndices', np.int32).reshape(-1, 3)
        uv_name = 'primvars:st' if re.search(r'\bprimvars:st =', attrs) else 'primvars:st0'
        texcoords = usd_array(attrs, uv_name, np.float64).reshape(-1, 2)
        if len(texcoords) == len(faces) * 3:
            texcoords = texcoords.reshape(-1,3,2)
        else:
            texcoords = texcoords[faces]
        world = points @ transform[:3,:3] + transform[3,:3]
        yield name, world, faces, texcoords

def sample(texture, uv):
    h,w,_ = texture.shape
    u,v = np.moveaxis(uv % 1, -1, 0)
    return texture[np.clip(((1-v)*h).astype(int),0,h-1), np.clip((u*w).astype(int),0,w-1)]

def load(id):
    source = assets/f'Wardrobe/wardrobe-costume-{id}.usdz'
    text = read_stage(source)
    texture_files = [value.removeprefix('./') for value in archive.findall(text)]
    with zipfile.ZipFile(assets/f'Wardrobe/wardrobe-costume-{id}.usdz') as z:
        texture = np.array(Image.open(io.BytesIO(z.read(texture_files[0]))).convert('RGB'))
    return text, texture

def raster(meshes, texture, label):
    # Combine all RGB textures horizontally; scale each original chart into one tile.
    if not isinstance(texture, list): texture = [(meshes, texture)]
    size = 1024
    width = len(texture)*size
    atlas = np.empty((size, width, 3), dtype=np.uint8)
    corners = []
    for i, (objects, image) in enumerate(texture):
        atlas[:,i*size:(i+1)*size] = np.asarray(Image.fromarray(image).resize((size,size)))
        for _,points,faces,uv in objects:
            tiled = uv.copy()
            tiled[...,0] = (tiled[...,0] + i) / len(texture)
            corners.append(np.concatenate((points[faces],tiled),axis=2).reshape(-1,5))
    corner = np.concatenate(corners)
    h,w = atlas.shape[:2]
    filename = root/f'{label}.bin'
    with filename.open('wb') as file:
        file.write(struct.pack('iii',len(corner)//3,w,h))
        file.write(atlas.tobytes())
        file.write(corner.astype(np.float32).tobytes())
    canvas = Image.new('RGB',(390*4,570),'#ebedea')
    draw = ImageDraw.Draw(canvas)
    for i,angle in enumerate([0,45,90,180]):
        target = root/f'{label}-{angle}.ppm'
        subprocess.run([str(root/'raster'),str(filename),str(target),'390','545',str(math.radians(angle)),'.76','330'],check=True)
        im=Image.open(target)
        canvas.paste(im,(390*i,0))
        draw.text((390*i+10,548),f'{label} {angle}°',fill='#202020')
    canvas.save(root/f'{label}.jpg',quality=94)


AZIMUTH_STEPS = 720
ANGLES = np.linspace(0, 2 * np.pi, AZIMUTH_STEPS, endpoint=False)

def read_stage(source):
    return subprocess.run(["/usr/bin/usdcat", str(source)], check=True,
                          capture_output=True, text=True, timeout=30).stdout

def configure(resources, scratch):
    global assets, root, seed_data, body
    assets = resources.resolve()
    root = scratch.resolve()
    root.mkdir(parents=True, exist_ok=True)
    seed_data = list(meshes(read_stage(assets / "Characters" / "SeedCucumberMaster.usdz")))
    body = body_sections(seed_data[0][1])
def polar(points):
    return np.mod(np.arctan2(points[..., 1], points[..., 0]), 2 * np.pi)

def unit(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-12)

def periodic_radius(ring, center):
    relative = ring - center
    angles = polar(relative)
    radii = np.linalg.norm(relative, axis=1)
    order = np.argsort(angles)
    return np.interp(ANGLES, angles[order], radii[order], period=2*np.pi)

class CrossSections:
    def __init__(self, height, centers, radii):
        self.height = height
        self.centers = centers
        self.radii = radii

    def sample(self, points):
        y = points[:, 1]
        row = np.interp(y, self.height, np.arange(len(self.height)))
        lower = row.astype(np.int64)
        upper = np.minimum(lower + 1, len(self.height) - 1)
        f = row - lower
        center = self.centers[lower] + f[:, None] * (self.centers[upper] - self.centers[lower])
        vectors = points[:, [0, 2]] - center
        phi = polar(vectors) * AZIMUTH_STEPS / (2 * np.pi)
        start = phi.astype(np.int64) % AZIMUTH_STEPS
        end = (start + 1) % AZIMUTH_STEPS
        t = phi - np.floor(phi)
        left = self.radii[lower, start] * (1 - t) + self.radii[lower, end] * t
        right = self.radii[upper, start] * (1 - t) + self.radii[upper, end] * t
        radius = left + f * (right - left)
        return center, vectors, radius

    def clearance(self, points):
        _, vectors, radius = self.sample(points)
        distance = np.linalg.norm(vectors, axis=1) - radius
        valid = (points[:, 1] >= self.height[0]) & (points[:, 1] <= self.height[-1])
        return np.where(valid, distance, np.inf)

    def push_out(self, points, margin):
        center, vectors, radius = self.sample(points)
        distance = np.linalg.norm(vectors, axis=1)
        valid = (points[:, 1] >= self.height[0]) & (points[:, 1] <= self.height[-1])
        moved = valid & (distance < radius + margin)
        points[np.ix_(moved, [0, 2])] = center[moved] + unit(vectors[moved]) * (radius[moved] + margin)[:, None]

def body_sections(points):
    rows = points.reshape(-1, 289, 3)[::-1]
    rings = rows[:, :, [0, 2]]
    centers = (np.max(rings, axis=1) + np.min(rings, axis=1)) / 2
    radii = np.stack([periodic_radius(ring, center) for ring, center in zip(rings, centers)])
    return CrossSections(rows[:, 0, 1], centers, radii)

def arm_sections(points, faces):
    edges = np.unique(np.sort(np.concatenate([faces[:, [0,1]], faces[:, [1,2]], faces[:, [2,0]]]), axis=1), axis=0)
    p1, p2 = points[edges[:, 0]], points[edges[:, 1]]
    low, high = np.minimum(p1[:, 1], p2[:, 1]), np.maximum(p1[:, 1], p2[:, 1])
    heights = np.arange(np.ceil(points[:,1].min()*1000), np.floor(points[:,1].max()*1000)+1)/1000
    centers, radii = [], []
    for height in heights:
        crossed = (low <= height) & (high > height)
        a, b = p1[crossed], p2[crossed]
        ratio = (height-a[:,1])/(b[:,1]-a[:,1])
        ring = (a + ratio[:,None]*(b-a))[:,[0,2]]
        center = (ring.min(axis=0)+ring.max(axis=0))*0.5
        centers.append(center)
        radii.append(periodic_radius(ring, center))
    return CrossSections(heights, np.stack(centers), np.stack(radii))

def smoothstep(values):
    t = np.clip(values, 0, 1)
    return t*t*(3-2*t)

def normals_for(points, faces):
    p0, p1, p2 = np.moveaxis(points[faces], 1, 0)
    face_normals = np.cross(p1-p0,p2-p0)
    lengths = np.linalg.norm(face_normals, axis=1)
    summed = np.zeros_like(points)
    for local in range(3):
        np.add.at(summed, faces[:,local], face_normals)
    return unit(summed), lengths
def skin_color(texture, uv):
    colors = sample(texture, uv.mean(axis=1)).astype(np.float64)
    r,g,b = colors.T
    return (g-r > 5) & (r-b > 11) & (g > 1.24*b)

def connected_pieces(points, faces, keep):
    # Vertex welding joins UV islands while leaving genuinely separate props alone.
    _, inverse = np.unique(np.round(points,6),axis=0,return_inverse=True)
    face_idx = np.flatnonzero(keep)
    f = inverse[faces[face_idx]]
    root_index = np.arange(inverse.max()+1)
    def group(i):
        while root_index[i]!=i:
            root_index[i]=root_index[root_index[i]]
            i=root_index[i]
        return i
    for a,b,c in f:
        a,b,c=group(a),group(b),group(c)
        root_index[b]=a;root_index[c]=a
    groups = np.array([group(i) for i in f[:,0]])
    return [(face_idx[groups==key],int(size)) for key,size in zip(*np.unique(groups,return_counts=True))]

def as_mesh(name, points, faces, uv):
    material_path = '</SeedCostume/Materials/mat0>'
    normals, area = normals_for(points,faces)
    valid=area>1e-13
    faces, uv = faces[valid], uv[valid]
    used, indices = np.unique(faces,return_inverse=True)
    normals = normals[faces].reshape(-1,3)
    points = points[used]
    return f'''    def Mesh "{name}" (
        prepend apiSchemas = ["MaterialBindingAPI"]
    )
    {{
        uniform bool doubleSided = true
        uniform token subdivisionScheme = "none"
        rel material:binding = {material_path}
        float3[] extent = {float_array([points.min(axis=0),points.max(axis=0)])}
        point3f[] points = {float_array(points)}
        int[] faceVertexCounts = [{", ".join(["3"]*len(faces))}]
        int[] faceVertexIndices = [{", ".join(map(str,indices.reshape(-1)))}]
        normal3f[] normals = {float_array(normals)} (
            interpolation = "faceVarying"
        )
        texCoord2f[] primvars:st = {float_array(uv.reshape(-1,2))} (
            interpolation = "faceVarying"
        )
    }}
'''

def float_array(values):
    return "[" + ", ".join("(" + ", ".join(f"{v:.8g}" for v in value) + ")" for value in values) + "]"

def render_seed(id, converted, texture, hidden, output):
    packages = [(converted, texture)]
    texture_root = assets/'Characters/SeedCucumberMaster.usdz'
    with zipfile.ZipFile(texture_root) as archive:
        for part in seed_data:
            name=part[0]
            if name in hidden: continue
            suffix='BodyBaseColor' if name=='Body' else name
            image=np.asarray(Image.open(io.BytesIO(archive.read(f'Textures/{suffix}.png'))).convert('RGB'))
            packages.append(([part],image))
    raster(None, packages, id+'-overlay')

def prepare(id, output, mask: Callable, fit: Callable, hidden=(), render=True, clean_color=None):
    text, texture = load(id)
    parts=[]
    output.mkdir(exist_ok=True,parents=True)
    for name,p,f,uv in meshes(text):
        if name in ("CenteredTail","RestoredRearFabric"):
            keep=np.full(len(f),True)
        else:
            keep=mask(p[f].mean(axis=1),skin_color(texture,uv),sample(texture,uv.mean(axis=1)).astype(float),name)
            filtered=np.zeros_like(keep)
            for indices,count in connected_pieces(p,f,keep):
                if count>=18: filtered[indices]=True
            keep=filtered
        p=fit(p.copy(),f[keep],name)
        parts.append((name,p,f[keep],uv[keep]))
    stage = '#usda 1.0\n(\n    defaultPrim = "SeedCostume"\n    metersPerUnit = 1\n    upAxis = "Y"\n)\ndef Xform "SeedCostume"\n{\n'
    stage += ''.join(as_mesh(name,p,f,uv) for name,p,f,uv in parts if len(f))
    scope=re.search(r'(?ms)^    def Scope "_materials"\n    \{.*?^    \}',text)[0]
    scope=scope.replace('def Scope "_materials"','def Scope "Materials"')
    scope=re.sub(r'</(?:OiCostume|OiCloset)/_materials/',r'</SeedCostume/Materials/',scope)
    stage += scope+'\n}\n'
    basename=f'seed-costume-{id}'
    (output/f'{basename}.usda').write_text(stage)
    entries=[entry.removeprefix('./') for entry in archive.findall(scope)]
    with zipfile.ZipFile(assets/f'Wardrobe/wardrobe-costume-{id}.usdz') as source:
        for entry in entries:
            target=output/entry
            target.parent.mkdir(exist_ok=True,parents=True)
            if clean_color is not None and entry == entries[0]:
                texture=clean_color(texture)
                Image.fromarray(texture).save(target, quality=97, subsampling=0)
            else:
                target.write_bytes(source.read(entry))
    for command in [
        ['/usr/bin/usdcat','-o',f'{basename}.usdc',f'{basename}.usda'],
        ['/usr/bin/usdzip',f'{basename}.usdz',f'{basename}.usdc',*entries],
        ['/usr/bin/usdchecker','--strict','--arkit',f'{basename}.usdz'],
    ]:
        subprocess.run(command,cwd=output,check=True,timeout=25)
    if render: render_seed(id,parts,texture,hidden,output)
    print(id, 'tris', [len(f) for _,p,f,uv in parts], 'hidden',hidden,flush=True)

def replace_baked_green(texture, color):
    """Remove exposed green source-body texels around the trimmed cloth edges."""
    rgb=texture.astype(np.int16)
    r,g,b=np.moveaxis(rgb,-1,0)
    green=(g-r>3)&(g-b>6)&(b<153)
    # Smooth against nearby cloth texels; an authored matching color fills
    # source areas which were entirely occupied by the old cucumber.
    good=(np.linalg.norm(rgb-np.asarray(color),axis=2)<62)&(~green)
    for _ in range(4):
        offsets=[(0,1),(0,-1),(1,0),(-1,0)]
        neighbors=[np.roll(np.roll(good,x,axis=0),y,axis=1) for x,y in offsets]
        nearby=np.sum(neighbors,axis=0)
        propagated=sum(np.roll(np.roll(rgb,x,axis=0),y,axis=1)*match[:,:,None]
                       for (x,y),match in zip(offsets,neighbors))
        fill=green&(~good)&(nearby>0)
        rgb[fill]=propagated[fill]//nearby[fill,None]
        good[fill]=True
    rgb[green&(~good)]=color
    return rgb.astype(np.uint8)

def smooth_body_fit(p,faces,name):
    # Smoothly give the original pieces enough room for the neutral character.
    p[:,2] *= 1.08
    p[:,2] += .012
    p[:,0] *= 1.055
    body.push_out(p, .010)
    return p

def ribbon_school(co,green,rgb,name):
    x,y,z=co.T
    r,g,b=rgb.T
    bow=(r-g>18)&(r-b>12)
    cloth=((y>=.221)&(y<.824))&(~green)
    shoes=(y<.096)&(~green)
    return cloth|shoes|((y>1.19)&bow)

def school_fit(p,faces,name):
    x,y,z=p.T.copy()
    p=smooth_body_fit(p,faces,name)
    # Map the old shoes to the lower end of the two narrower bare legs.
    fit_boots(p,x,y,z,.097,source_x=.116,target_x=.134,
              source_z=.025,target_z=.008,width=1.36,depth=1.44)
    return p

def fit_boots(p,x,y,z,height,source_x,target_x,source_z,target_z,width,depth):
    shoe = y < height
    p[shoe,0] = np.sign(x[shoe]) * (target_x + width*(np.abs(x[shoe])-source_x))
    p[shoe,2] = target_z + depth*(z[shoe]-source_z)
