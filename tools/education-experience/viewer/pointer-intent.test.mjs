import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PointerIntent} from './pointer-intent.mjs';

test('a tap is recognized only on release',() => {
  const p = new PointerIntent(); assert.equal(p.begin(1,50,50),true); assert.equal(p.mode,'pending');
  assert.equal(p.end(1,50,50),true); assert.equal(p.mode,'idle');
});
test('small finger jitter does not rotate',() => {
  const p = new PointerIntent(); p.begin(1,50,50); assert.equal(p.move(1,53,52),null); assert.equal(p.end(1,50,50),true);
});
test('crossing the tolerance permanently cancels a tap, even after returning',() => {
  const p = new PointerIntent(); p.begin(1,50,50); assert.equal(p.move(1,70,50).kind,'rotate');
  p.move(1,50,50); assert.equal(p.end(1,50,50),false);
});
test('a release far from start cancels a tap without intermediate move events',() => {
  const p = new PointerIntent(); p.begin(1,50,50); assert.equal(p.end(1,80,50),false);
});
test('pinch changes scale and does not rotate',() => {
  const p = new PointerIntent(); p.begin(1,0,0); p.begin(2,20,0);
  assert.deepEqual(p.move(2,40,0),{kind:'zoom',ratio:2});
  assert.equal(p.end(2,40,0),false); assert.equal(p.move(1,1,0),null); assert.equal(p.end(1,1,0),false);
});
test('two fingers lifted without moving are never a tap',() => {
  const p = new PointerIntent(); p.begin(1,0,0); p.begin(2,20,0);
  assert.equal(p.end(1,0,0),false); assert.equal(p.end(2,20,0),false);
});
test('a third pointer keeps the gesture blocked until all pointers leave',() => {
  const p = new PointerIntent(); p.begin(1,0,0); p.begin(2,20,0); p.begin(3,30,0);
  assert.equal(p.end(3,30,0),false); assert.equal(p.move(1,2,0),null);
  assert.equal(p.end(1,2,0),false); assert.equal(p.end(2,20,0),false);
});
test('cancellation and lost capture cannot activate a building',() => {
  const p = new PointerIntent(); p.begin(1,50,50); assert.equal(p.end(1,50,50,true),false);
  assert.equal(p.end(1,50,50),false);
});
test('secondary mouse buttons do not start a gesture',() => {
  const p = new PointerIntent(); assert.equal(p.begin(1,50,50,2),false); assert.equal(p.end(1,50,50),false);
});
test('zero-distance pinch never produces an infinite scale',() => {
  const p = new PointerIntent(); p.begin(1,0,0); p.begin(2,0,0);
  assert.equal(p.move(2,20,0).ratio,1); assert.equal(p.move(2,40,0).ratio,2);
});
test('a new gesture works after a multi-touch gesture or interruption',() => {
  const p = new PointerIntent(); p.begin(1,0,0); p.begin(2,20,0); p.reset();
  assert.equal(p.end(1,0,0),false); p.begin(3,10,10); assert.equal(p.end(3,10,10),true);
});
