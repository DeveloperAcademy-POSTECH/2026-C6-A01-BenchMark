// A single, continuous 3D study of the four supplied building views.
// +Z is the main entrance, -X is the raised hall, +X is the amphitheatre.
// Dimensions are relative image measurements, not construction measurements.
export const CAPACITY = 96000;
export const MOBILE_POINT_COUNT = 48000;
export const LIGHT_POINT_COUNT = 24000;
export const MINE_ID = CAPACITY - 1;
export const GEOMETRY_REVISION = 'fine-packed-building-surfaces-5';
export const CAMERA_VIEWS = {
  // Side references include some of the adjoining elevation, not flat plans.
  front:{yaw:0,pitch:.26}, left:{yaw:1.25,pitch:.26},
  right:{yaw:-1.95,pitch:.26}, back:{yaw:Math.PI,pitch:.26}
};
export function randomGenerator(seed = 2077) {
  return () => {seed|=0;seed=seed+0x6D2B79F5|0;let t=Math.imul(seed^seed>>>15,1|seed);t=t+Math.imul(t^t>>>7,61|t)^t;return ((t^t>>>14)>>>0)/4294967296;};
}
const TAU=Math.PI*2, CENTER_Y=2.18;
const mix=(a,b,t)=>a+(b-a)*t;
const unit=a=>{const n=Math.hypot(...a)||1;return a.map(v=>v/n);};
const cross=(a,b)=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];

// Rounded irregular polygons, sampled by distance, keep long faces straight.
// Unlike a rounded box, every terrace has a distinct setback and plan shape.
function plan(vertices,radius=.32) {
  const raw=[];
  for(let i=0;i<vertices.length;i++){
    const p=vertices[(i+vertices.length-1)%vertices.length],q=vertices[i],r=vertices[(i+1)%vertices.length];
    const a=Math.min(radius,Math.hypot(q[0]-p[0],q[1]-p[1])*.3),b=Math.min(radius,Math.hypot(q[0]-r[0],q[1]-r[1])*.3);
    const d1=unit([p[0]-q[0],p[1]-q[1]]),d2=unit([r[0]-q[0],r[1]-q[1]]);
    const start=[q[0]+d1[0]*a,q[1]+d1[1]*a],end=[q[0]+d2[0]*b,q[1]+d2[1]*b];
    for(let j=0;j<=12;j++){const t=j/12,s=1-t;raw.push([s*s*start[0]+2*s*t*q[0]+t*t*end[0],s*s*start[1]+2*s*t*q[1]+t*t*end[1]]);}
  }
  const lengths=[0];
  for(let i=0;i<raw.length;i++){const a=raw[i],b=raw[(i+1)%raw.length];lengths.push(lengths.at(-1)+Math.hypot(a[0]-b[0],a[1]-b[1]));}
  const total=lengths.at(-1);
  const at=t=>{const d=((t%1)+1)%1*total;let lo=0,hi=raw.length;while(lo+1<hi){const m=(lo+hi)>>1;if(lengths[m]<=d)lo=m;else hi=m;}const f=(d-lengths[lo])/(lengths[lo+1]-lengths[lo]);return raw[lo].map((v,k)=>mix(v,raw[(lo+1)%raw.length][k],f));};
  return {at,length:total};
}
const rect=(cx,cz,hx,hz,r=.2)=>plan([[cx-hx,cz-hz],[cx+hx,cz-hz],[cx+hx,cz+hz],[cx-hx,cz+hz]],r);
const transform=(p,sx,sz,dx=0,dz=0)=>({length:p.length*Math.max(sx,sz),at:t=>{const[x,z]=p.at(t);return[x*sx+dx,z*sz+dz];}});
const silhouette=[[-5.15,-1.48],[-4.58,-2.02],[3.77,-2.02],[4.97,-1.42],[5.20,.65],[4.62,1.48],[1.18,2.04],[-4.52,2.04],[-5.19,1.31]];
const ring=transform(plan(silhouette,.42),1,1.45);
const podiumPlans=[
  plan([[-5.65,-2.57],[4.90,-2.57],[5.77,-1.92],[6.06,2.33],[5.49,3.03],[1.10,3.03],[.22,2.64],[-2.65,2.64],[-2.65,2.87],[-5.65,2.87]],.46),
  plan([[-5.45,-2.39],[4.58,-2.39],[5.37,-1.62],[5.55,1.84],[5.05,2.45],[1.01,2.45],[-.06,2.30],[-2.65,2.30],[-2.65,2.87],[-5.45,2.87]],.43),
  plan([[-5.03,-2.12],[4.10,-2.12],[4.96,-1.40],[5.09,1.18],[4.52,1.93],[1.45,2.00],[.65,1.64],[-4.56,1.64],[-5.03,1.12]],.38)
].map(p=>transform(p,1,1.45));

export function buildGeometry(){
  const candidates=[],triangles=[],groups={},rng=randomGenerator(402026);
  let group='';
  const add=(p,n,b)=>{if(!p.every(Number.isFinite))throw new Error('Invalid building surface');candidates.push({p:[p[0],p[1]-CENTER_Y,p[2]],n,b,group});groups[group]=(groups[group]||0)+1;};
  const triangle=(a,b,c)=>{for(const p of[a,b,c])triangles.push(p[0],p[1]-CENTER_Y,p[2]);};
  // The depth-only shell is never coloured: it hides the far side's points,
  // leaving an actual open courtyard instead of transparent stacked outlines.
  function surface(name,fn,nu,nv,brightness=.7,normalHint=null,occludes=true,visible=()=>true){
    group=name;
    // More rows, rather than larger sprites, supply continuous surface coverage.
    nu=Math.ceil(nu*1.4);nv=Math.ceil(nv*1.4);
    const normal=(u,v)=>{
      if(normalHint)return normalHint(u,v);
      const d=.0001,a=fn(u+d,v),b=fn(u-d,v),c=fn(u,Math.min(1,v+d)),e=fn(u,Math.max(0,v-d));
      return unit(cross(c.map((x,k)=>x-e[k]),a.map((x,k)=>x-b[k])));
    };
    for(let v=0;v<=nv;v++)for(let u=0;u<nu;u++){
      const uu=(u+(v%2)*.5)/nu,vv=v/nv;
      const light=typeof brightness==='function'?brightness(uu,vv,u,v):brightness;
      const p=fn(uu,vv);if(visible(p)){add(p,normal(uu,vv),light);candidates.at(-1).row=v;}
    }
    if(occludes){
      const su=Math.min(96,nu),sv=Math.min(8,nv);
      for(let v=0;v<sv;v++)for(let u=0;u<su;u++){
        const a=fn(u/su,v/sv),b=fn((u+1)/su,v/sv),c=fn((u+1)/su,(v+1)/sv),d=fn(u/su,(v+1)/sv);
        const mid=a.map((x,k)=>(x+b[k]+c[k]+d[k])/4);
        if(visible(mid)){triangle(a,b,c);triangle(a,c,d);}
      }
    }
  }
  const up=()=>[0,1,0];
  function wall(name,p,y0,y1,light=.65,spacing=.065){
    surface(name,(u,v)=>{const[x,z]=p.at(u);return[x,mix(y0,y1,v),z];},Math.ceil(p.length/.071),Math.max(2,Math.ceil((y1-y0)/spacing)),light);
  }
  function ribbon(name,p,y,width=.12,height=.13){
    wall(name,p,y-height,y,.78,.047);
    const inner=transform(p,1-width/5.5,1-width/2.5);
    surface(name+' coping',(u,v)=>{const a=p.at(u),b=inner.at(u);return[mix(a[0],b[0],v),y,mix(a[1],b[1],v)];},Math.ceil(p.length/.065),3,.80,up);
  }
  function deck(name,outer,inner,y,brightness=.72,visible=()=>true){
    surface(name,(u,v)=>{const a=outer.at(u),b=inner.at(u);return[mix(a[0],b[0],v),y,mix(a[1],b[1],v)];},Math.ceil(outer.length/.075),18,brightness,up,true,visible);
  }
  function box(name,x0,x1,y0,y1,z0,z1){
    const p=rect((x0+x1)/2,(z0+z1)/2,(x1-x0)/2,(z1-z0)/2,.025);
    wall(name,p,y0,y1,.64,.065);
    surface(name+' roof',(u,v)=>[mix(x0,x1,u),y1,mix(z0,z1,v)],Math.ceil((x1-x0)/.08),Math.ceil((z1-z0)/.08),.7,up);
  }
  function outline(p,y,brightness=1.0){
    group='architectural edges';
    const count=Math.ceil(p.length/.045);
    for(let i=0;i<count;i++){const[x,z]=p.at(i/count),a=p.at(i/count-.0001),b=p.at(i/count+.0001);add([x,y,z],unit([b[1]-a[1],.5,a[0]-b[0]]),brightness);}
  }

  // Three set-back glazed floors. Their horizontal terrace bands wrap around
  // the right end; the solid service volume is only on the left end.
  const levels=[.26,.92,1.57];
  for(let i=0;i<3;i++){
    const outer=podiumPlans[i],glass=transform(outer,.93,.85,0,-.035),y=levels[i];
    ribbon('terrace '+i,outer,y,.17,.12);
    // The exposed terrace runs to the NEXT floor's setback. Stopping at this
    // floor's glazing left the middle of each step entirely without samples.
    const setback=i<2?transform(podiumPlans[i+1],.93,.85,0,-.035):transform(ring,.905,.82);
    deck('terrace paving '+i,outer,setback,y,.74,p=>i!==0||((p[0]-4.53)/1.09)**2+((p[2]-3.35)/.69)**2>1);
    outline(outer,y+.005);outline(outer,y-.115,.88);
    const bottom=i===0?-.02:levels[i-1]+.02;
    wall('podium glazing '+i,glass,bottom,y-.12,(u,v,iu,iv)=>iv===0||iv%5===0?.75:.60,.065);
    // Glass mullions are vertical, independent of the horizontal slab points.
    group='podium mullions';
    for(let j=0;j<Math.floor(glass.length/.31);j++){
      const[x,z]=glass.at(j/Math.floor(glass.length/.31));
      for(let h=bottom;h<y-.1;h+=.065)add([x,h,z],unit([x,0,z]),.64);
    }
    wall('terrace balustrade '+i,transform(outer,.995,.989),y+.035,y+.16,.55,.065);
  }
  // Rounded stone wall below the raised hall, rather than a full solid base.
  const leftWall=rect(-4.12,.02,1.49,3.9,.46);
  wall('left stone podium',leftWall,.01,1.17,(u,v,iu,iv)=>iv%2?.57:.77,.058);
  deck('left planted terrace',leftWall,rect(-4.12,.02,.04,.04,.015),1.18,.70);
  ribbon('left parapet',leftWall,1.20,.11,.09);
  outline(leftWall,1.205);
  for(const y of[.03,.26,.49,.72,.95])outline(leftWall,y,.76);

  // Large floating horizontal-louvre belt: bevelled underside, broad vertical
  // face, rounded right tip. It is NOT three identical rounded rectangles.
  surface('silver louvre facade',(u,v)=>{
    const [x,z]=ring.at(u),bevel=Math.min(1,v/.34),s=.905+.095*bevel;
    return[x*s,1.81+v*1.24,z*(.82+.18*bevel)];
  },Math.ceil(ring.length/.042),40,(u,v,iu,iv)=>iv%3===0?.90:.72);
  outline(ring,3.055);
  // An upper lip curls inward around the real open roof courtyard.
  const inner=rect(.32,0,3.46,2.0,.38);
  surface('roof louvre rim',(u,v)=>{
    const a=ring.at(u),b=inner.at(u);
    return[mix(a[0],b[0],v),3.05+.22*v,mix(a[1],b[1],v)];
  },Math.ceil(ring.length/.057),22,(u,v,iu,iv)=>iv%3?.74:.90,up);
  surface('courtyard glazing',(u,v)=>{const[x,z]=inner.at(u);return[x,mix(2.83,3.27,v),z];},Math.ceil(inner.length/.071),8,.64,(u)=>{const[x,z]=inner.at(u);return unit([.32-x,0,-z]);});
  surface('open courtyard floor',(u,v)=>[mix(-2.13,3.51,u),2.83,mix(-1.95,1.95,v)],92,58,(u,v,iu,iv)=>(iu%8===0||iv%7===0)?.80:.68,up);
  // Smaller glazed rooftop lantern in the rear of the court.
  box('courtyard lantern',-.35,.63,2.84,3.55,-2.15,-1.55);
  for(let j=0;j<6;j++){
    group='lantern roof ribs';
    for(let z=-2.15;z<=-1.55;z+=.055)add([-.35+j*.196,3.56,z],[0,1,0],.95);
  }

  // Tapered hall at the left, a little under 1/3 of the main facade length.
  const hall=rect(-3.52,-.03,1.40,1.75,.16);
  wall('hall glass base',hall,3.05,3.34,.65,.065);
  surface('tapered hall louvers',(u,v)=>{
    const[x,z]=hall.at(u);return[-3.52+(x+3.52)*mix(1,.70,v),mix(3.34,4.55,v),-.03+(z+.03)*mix(1,.66,v)];
  },Math.ceil(hall.length/.042),32,(u,v,iu,iv)=>iv%3?.72:.90);
  const hallTop=rect(-3.52,-.03,.98,1.155,.13);
  surface('hall roof glass',(u,v)=>[mix(-4.46,-2.58,u),4.55,mix(-1.14,1.08,v)],38,44,.70,up);
  ribbon('hall roof perimeter',hallTop,4.58,.09,.04);
  group='hall skylight ribs';
  for(let j=0;j<6;j++)for(let z=-1.14;z<=1.08;z+=.048)add([-4.46+j*.376,4.585,z],[0,1,0],1.0);

  // The bridge projects from the left end, visible from front and rear.
  box('left glass bridge',-6.35,-4.72,1.33,1.66,-.50,.13);
  group='bridge beams';
  for(let y of[1.33,1.66])for(let z of[-.5,.13])for(let x=-6.35;x<=-4.72;x+=.055)add([x,y,z],[0,1,0],.98);

  // Right-side amphitheatre: nested curved stairs on the lowest terrace.
  // The omitted deck patch makes it a sunken bowl instead of a stack of lines.
  const bowlCenter=[4.53,3.35];
  for(let i=0;i<7;i++){
    const rx=1.03-i*.105,rz=.63-i*.055,y=.30-i*.026;
    surface('amphitheatre '+i,(u,v)=>{const a=Math.PI*.12+u*Math.PI*1.76;return[bowlCenter[0]+Math.cos(a)*(rx-v*.06),y,bowlCenter[1]+Math.sin(a)*(rz-v*.025)];},Math.ceil(rx*TAU/.05),2,.95,up,false);
  }
  // Diagonal promenade braces are visible on both long elevations.
  for(const sign of[1,-1]){
    surface('diagonal terrace brace',(u,v)=>[mix(2.45,3.23,v)+u*.16,mix(.94,1.55,v),sign*2.90],3,16,.8,()=>[0,0,sign]);
  }

  // Keep the reference's horizontal courses, filling between them with small,
  // evenly spaced spheres. Four interleaved tiers keep lower-detail surfaces
  // evenly covered instead of drawing a random, hole-filled subset.
  const importance=name=>name==='architectural edges'?.18:name==='silver louvre facade'?.72:name==='tapered hall louvers'?1.0:name==='left stone podium'?2.2:name==='roof louvre rim'?.65:name.includes('glazing')?2.6:name.includes('ribs')||name.includes('beams')?.65:name.includes('mullions')?.65:name.includes('paving')||name==='open courtyard floor'?.65:name.includes('coping')?.35:name.includes('balustrade')?.4:name.includes('amphitheatre')?1.1:1;
  const buckets=new Map();for(const p of candidates){if(!buckets.has(p.group))buckets.set(p.group,[]);buckets.get(p.group).push(p);}
  const totalWeight=[...buckets].reduce((sum,[name,points])=>sum+points.length*importance(name),0);
  const selected=[];
  for(const[name,points]of buckets){
    const count=Math.min(points.length,Math.floor(CAPACITY*points.length*importance(name)/totalWeight));
    // Allocate each horizontal row separately. Flattened stride sampling made
    // the facade appear to have diagonal ribs that the reference never had.
    const rows=new Map();for(const p of points){const key=p.row??-1;if(!rows.has(key))rows.set(key,[]);rows.get(key).push(p);}
    let sampledRows=[...rows.values()];
    if(sampledRows.length>4&&count>1000){
      // Balance spacing in world units. Keeping every source row while
      // thinning only the columns produced tall chains of beads and gaps.
      const rowLength=row=>row.slice(1).reduce((sum,p,i)=>sum+Math.hypot(...p.p.map((x,k)=>x-row[i].p[k])),0);
      const width=sampledRows.reduce((sum,row)=>sum+rowLength(row),0)/sampledRows.length;
      let height=0;
      for(let r=1;r<sampledRows.length;r++){
        for(const u of[.125,.375,.625,.875]){
          const a=sampledRows[r-1][Math.floor(u*sampledRows[r-1].length)].p,b=sampledRows[r][Math.floor(u*sampledRows[r].length)].p;
          height+=Math.hypot(...a.map((x,k)=>x-b[k]))/4;
        }
      }
      const rowCount=Math.min(sampledRows.length,Math.max(2,Math.ceil(Math.sqrt(count*height/Math.max(.01,width)))+1,Math.ceil(count/Math.min(...sampledRows.map(row=>row.length)))));
      sampledRows=Array.from({length:rowCount},(_,i)=>sampledRows[Math.round(i*(sampledRows.length-1)/(rowCount-1))]);
    }
    const sampleTotal=sampledRows.reduce((sum,row)=>sum+row.length,0);
    let visited=0,allocated=0;
    for(let r=0;r<sampledRows.length;r++){
      const row=sampledRows[r];
      visited+=row.length;const end=Math.round(count*visited/sampleTotal),n=end-allocated;allocated=end;
      const v=r;
      for(let i=0;i<n;i++){
        // Offset alternate rows by half a sample and interpolate along each
        // continuous surface instead of snapping to the coarser source grid.
        const at=(i+(v%2?.75:.25))*row.length/n,index=Math.min(row.length-1,Math.floor(at)),a=row[index],b=row[Math.min(row.length-1,index+1)],t=at-index;
        const continuous=a.row!==undefined&&Math.hypot(...a.p.map((x,k)=>x-b.p[k]))<.22;
        const p=continuous?{...a,p:a.p.map((x,k)=>mix(x,b.p[k],t)),n:unit(a.n.map((x,k)=>mix(x,b.n[k],t))),b:mix(a.b,b.b,t)}:{...a};
        p.tier=v%2?(i%2?1:3):(i%2?2:0);selected.push(p);
      }
    }
  }
  const seen=new Set(selected);for(const p of candidates){if(selected.length>=CAPACITY)break;if(!seen.has(p)){selected.push(p);seen.add(p);}}
  const tiers=Array.from({length:4},()=>[]);
  for(const p of selected)tiers[p.tier??Math.floor(rng()*4)].push(p);
  selected.length=0;
  for(const tier of tiers){
    for(let i=tier.length-1;i>0;i--){const j=Math.floor(rng()*(i+1));[tier[i],tier[j]]=[tier[j],tier[i]];}
    for(const p of tier)selected.push(p);
  }
  if(candidates.length<CAPACITY)throw new Error('Not enough architectural samples');
  const vertices=new Float32Array(CAPACITY*11),positions=new Float32Array(CAPACITY*3),clouds=new Float32Array(CAPACITY*3),ids=new Uint32Array(CAPACITY),selectedGroups={};
  let mineIndex=0;
  for(let i=0;i<CAPACITY;i++){
    const {p,n,b,group}=selected[i],id=(i%LIGHT_POINT_COUNT)*(CAPACITY/LIGHT_POINT_COUNT)+Math.floor(i/LIGHT_POINT_COUNT);
    const a=rng()*TAU,u=rng()*2-1,r=2.7+Math.cbrt(rng())*3.1;
    const c=[Math.cos(a)*Math.sqrt(1-u*u)*r*1.25,u*r*.7,Math.sin(a)*Math.sqrt(1-u*u)*r*.72];
    vertices.set([...p,...c,id,b,...n],i*11);positions.set(p,i*3);clouds.set(c,i*3);ids[i]=id;
    selectedGroups[group]=(selectedGroups[group]||0)+1;if(id===MINE_ID)mineIndex=i;
  }
  return{vertices,positions,clouds,ids,mineIndex,candidateCount:candidates.length,occluders:new Float32Array(triangles),groups:selectedGroups,revision:GEOMETRY_REVISION};
}
export function projectPoint(x,y,z,yaw,pitch,distance,aspect){
  const cy=Math.cos(yaw),sy=Math.sin(yaw),cp=Math.cos(pitch),sp=Math.sin(pitch),rx=x*cy+z*sy,rz=-x*sy+z*cy;
  const ry=y*cp-rz*sp,cameraZ=distance-y*sp-rz*cp;
  return[rx*1.83/aspect/cameraZ,ry*1.83/cameraZ,cameraZ];
}

// Fit the same silhouette at desktop and phone aspect ratios. Leave space for
// the view controls above and the scatter action below the building.
export function fitCameraDistance(positions,yaw,pitch,aspect){
  let distance=6;
  const cy=Math.cos(yaw),sy=Math.sin(yaw),cp=Math.cos(pitch),sp=Math.sin(pitch);
  for(let i=0;i<positions.length;i+=3){
    const x=positions[i]*cy+positions[i+2]*sy,z=-positions[i]*sy+positions[i+2]*cy;
    const y=positions[i+1]*cp-z*sp,vz=positions[i+1]*sp+z*cp;
    distance=Math.max(distance,vz+Math.abs(x)*1.83/(aspect*.87),vz+Math.abs(y)*1.83/.66);
  }
  return distance;
}
