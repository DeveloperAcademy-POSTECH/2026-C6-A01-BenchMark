import assert from 'node:assert/strict';
import {buildGeometry,CAPACITY,MINE_ID,CAMERA_VIEWS,projectPoint,fitCameraDistance,MOBILE_POINT_COUNT,LIGHT_POINT_COUNT} from '../dist/geometry.js';

const g=buildGeometry(),again=buildGeometry();
assert.equal(g.positions.length,CAPACITY*3);
assert.equal(g.vertices.length,CAPACITY*11);
assert.equal(new Set(g.ids).size,CAPACITY);
assert.equal(g.ids[g.mineIndex],MINE_ID);
assert.deepEqual(g.vertices,again.vertices,'reload must preserve each donor position');
assert.deepEqual(g.occluders,again.occluders);
for(const data of[g.positions,g.clouds,g.vertices,g.occluders])assert(data.every(Number.isFinite));
for(let i=0;i<CAPACITY;i++){
  const n=Math.hypot(...g.vertices.slice(i*11+8,i*11+11));
  assert(Math.abs(n-1)<1e-5,'surface normals must be unit length');
}

// Reduced detail must still represent the complete donation range, including
// near-empty and near-full states; the personal orb is rendered separately.
for(const count of[LIGHT_POINT_COUNT,MOBILE_POINT_COUNT,CAPACITY]){
  const ids=g.ids.slice(0,count);
  for(let percent=0;percent<=100;percent++){
    const verified=Math.round(CAPACITY*percent/100);
    const visible=ids.reduce((n,id)=>n+Number(id<verified),0);
    assert(Math.abs(visible-count*percent/100)<=1);
  }
}

// All four named views fit without cropping at narrow phone, portrait tablet,
// and wide desktop proportions.
for(const aspect of[.65,390/370,.9,1.6,2.0]){
  for(const [name,{yaw,pitch}] of Object.entries(CAMERA_VIEWS)){
    const distance=fitCameraDistance(g.positions,yaw,pitch,aspect);
    for(let i=0;i<g.positions.length;i+=3){
      const [x,y,z]=projectPoint(...g.positions.slice(i,i+3),yaw,pitch,distance,aspect);
      assert(z>.2);
      assert(Math.abs(x)<=.87001 && Math.abs(y)<=.66001,name+' silhouette cropped');
    }
  }
}

// Top-down depth probes: an open court must stop at its recessed paving, not a
// lid over the whole building. The taller hall must remain on the left.
function topAt(x,z){
  let top=-Infinity;
  for(let i=0;i<g.occluders.length;i+=9){
    const a=g.occluders.slice(i,i+3),b=g.occluders.slice(i+3,i+6),c=g.occluders.slice(i+6,i+9);
    const det=(b[2]-c[2])*(a[0]-c[0])+(c[0]-b[0])*(a[2]-c[2]);
    if(Math.abs(det)<1e-9)continue;
    const u=((b[2]-c[2])*(x-c[0])+(c[0]-b[0])*(z-c[2]))/det;
    const v=((c[2]-a[2])*(x-c[0])+(a[0]-c[0])*(z-c[2]))/det,w=1-u-v;
    if(Math.min(u,v,w)>=-1e-5)top=Math.max(top,u*a[1]+v*b[1]+w*c[1]);
  }
  return top;
}
for(const [x,z] of[[0,0],[1,0],[-1,0],[1,.8]])assert(Math.abs(topAt(x,z)-.65)<.02,'courtyard is closed');
assert(topAt(-3.5,0)>2.3 && topAt(3.5,0)<1.2,'raised hall is on wrong end');
for(const feature of['silver louvre facade','tapered hall louvers','left glass bridge','amphitheatre 0','terrace 0','terrace 1','terrace 2'])assert(g.groups[feature]>0);
// A dense silhouette alone is insufficient: the three lower storeys and their
// exposed terraces must retain a substantial share of the surface samples.
const lowerWalls=[0,1,2].reduce((n,i)=>n+g.groups['podium glazing '+i],0);
const paving=[0,1,2].reduce((n,i)=>n+g.groups['terrace paving '+i],0);
assert(lowerWalls>CAPACITY*.20,'lower storey faces are too sparse');
assert(paving>CAPACITY*.12,'terrace surfaces are too sparse');
assert(g.groups['architectural edges']<CAPACITY*.02,'outlines dominate the point budget');
const gpuBufferBytes=g.vertices.byteLength+g.occluders.byteLength;
assert(gpuBufferBytes<6*1024*1024,'static buffers exceeded the mobile memory budget');
console.log(JSON.stringify({status:'passed',capacity:CAPACITY,candidates:g.candidateCount,depthTriangles:g.occluders.length/9,gpuBufferBytes,views:Object.keys(CAMERA_VIEWS),lodCounts:[LIGHT_POINT_COUNT,MOBILE_POINT_COUNT,CAPACITY]},null,2));
