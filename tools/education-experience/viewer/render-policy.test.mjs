import {test} from 'node:test';
import assert from 'node:assert/strict';
import {frameQueue,framingPoints,scatterData,scatterScale,renderPolicy,morphFraming} from './render-policy.mjs';

test('pointer bursts collapse into one draw of the latest state',()=>{
  const frames=new Map();let next=0,draws=0,state=0,drawn;
  const queue=frameQueue(()=>{draws++;drawn=state;},fn=>{frames.set(++next,fn);return next;},id=>frames.delete(id));
  for(let i=0;i<80;i++){state=i;queue.schedule();}
  assert.equal(frames.size,1);frames.get(1)();frames.delete(1);
  assert.equal(draws,1);assert.equal(drawn,79);
  queue.schedule();queue.cancel();assert.equal(frames.size,0);
  queue.schedule();assert.equal(frames.size,1);
});
test('framing support retains original extremes with a small fixed budget',()=>{
  const points=[];for(let x=-4;x<=4;x++)for(let y=0;y<=4;y++)for(let z=-2;z<=2;z++)points.push(x,y,z);
  const result=framingPoints(points);
  assert.ok(result.length<=288);assert.ok(result.length<points.length/3);
  for(let axis=0;axis<3;axis++){
    assert.equal(Math.min(...result.map(p=>p[axis])),Math.min(...points.filter((_,i)=>i%3===axis)));
    assert.equal(Math.max(...result.map(p=>p[axis])),Math.max(...points.filter((_,i)=>i%3===axis)));
  }
});
test('scatter keeps exactly 10,000 distinct surface IDs and excludes backing',()=>{
  const model={sphereCount:12000,groups:[{name:'surface A',start:0,count:6000},{name:'backing',start:6000,count:1000},{name:'surface B',start:7000,count:5000}]};
  const positions=Float32Array.from({length:36000},(_,i)=>Math.sin(i)*4);
  const data=scatterData(model,positions);
  assert.equal(data.ids.length,10000);assert.equal(new Set(data.ids).size,10000);
  assert.ok(data.ids.every(id=>id<6000||id>=7000));
  assert.equal([...data.sizes].filter(x=>x>0).length,10000);
  assert.ok([...data.offsets].every(Number.isFinite));assert.ok(data.maxDisplacement<3);
});
test('morph framing preserves the building and the scattered endpoints with a fixed small cache',()=>{
  const positions=Float32Array.from({length:9000},(_,i)=>Math.sin(i*.13)*7);
  const ids=Array.from({length:2000},(_,i)=>i),offsets=Float32Array.from({length:9000},(_,i)=>Math.cos(i*.17));
  const {pairs,endpoints}=morphFraming(positions,{ids,offsets});
  assert.ok(pairs.length<=576);assert.equal(endpoints.length,6000);
  for(let axis=0;axis<3;axis++){
    const rest=Array.from(positions).filter((_,i)=>i%3===axis),spread=Array.from(endpoints).filter((_,i)=>i%3===axis);
    assert.equal(Math.min(...pairs.map(p=>p.from[axis])),Math.min(...rest));
    assert.equal(Math.max(...pairs.map(p=>p.from[axis])),Math.max(...rest));
    assert.ok(Math.min(...pairs.map(p=>p.to[axis]))<=Math.min(...spread)+.00001);
    assert.ok(Math.max(...pairs.map(p=>p.to[axis]))>=Math.max(...spread)-.00001);
  }
});
test('every shell and core returns to its exact original size; only chosen shells survive',()=>{
  for(const size of [0,1.5,2.05])for(const core of [false,true])assert.equal(scatterScale(size,0,core),1);
  assert.equal(scatterScale(0,1),0);assert.equal(scatterScale(1.7,1),1.7);assert.equal(scatterScale(1.7,1,true),0);
  assert.ok(scatterScale(1.7,.5)>1);
});
test('mobile geometry reduces triangle and transmission-pixel budgets',()=>{
  const triangles=([w,h])=>w*(h-1)*2;
  assert.ok(triangles(renderPolicy.shell)+triangles(renderPolicy.core)<224*.35*2);
  assert.ok((renderPolicy.pixelRatio*renderPolicy.transmissionScale)**2<1.5**2*.2);
});
