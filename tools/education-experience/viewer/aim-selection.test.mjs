import {test} from 'node:test';
import assert from 'node:assert/strict';
import {findAimedPearl,orbitPitch} from './aim-selection.mjs';
const matrix=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1];
const pick=(points,extra={})=>findAimedPearl({positions:points.flat(),ids:points.map((_,i)=>i),sizes:points.map(()=>1),matrix,width:400,height:800,x:200,y:600,radius:.01,...extra});
test('the lower fixed aim chooses a pearl independently of the finger position',()=>{
  assert.equal(pick([[.5,-.5,0],[.01,-.5,0],[0,.5,0]]).id,1);
});
test('offscreen and behind-camera pearls cannot supply a story',()=>{
  assert.equal(pick([[0,-.5,2],[0,-.5,0]]).id,1);
  assert.equal(pick([[2,-.5,0]]),null);
  assert.equal(pick([[0,-.5,0]],{matrix:[...matrix.slice(0,15),-1]}),null);
});
test('a nearby selection remains stable but moves to a clearly closer pearl',()=>{
  assert.equal(pick([[.03,-.5,0],[.02,-.5,0]],{previous:0}).id,0);
  assert.equal(pick([[.3,-.5,0],[.02,-.5,0]],{previous:0}).id,1);
});
test('scatter rotation reaches above and below the cloud without crossing a camera pole',()=>{
  assert.ok(orbitPitch(.2,4,true)>1.5);assert.ok(orbitPitch(.2,-4,true)<-1.5);
  assert.equal(orbitPitch(.2,4,false),.8);assert.equal(orbitPitch(.2,-4,false),.06);
});
