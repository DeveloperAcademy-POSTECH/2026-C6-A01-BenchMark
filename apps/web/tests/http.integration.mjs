import { test } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID, createHash } from 'node:crypto';

const origin = process.env.TEST_BASE_URL || 'http://127.0.0.1:4314';
assert.equal(new URL(origin).hostname, '127.0.0.1', 'HTTP fixtures must never run against a hosted Site');
const migrationToken = 'test-only-local-migration-key-at-least-32-characters';
const password = 'test-only-local-admin-password';

test('local Worker HTTP preserves admin authorization, reservation conversion, conflicts, photos, reactions and CSV', async () => {
  let cookie = '';
  async function request(path, options = {}) {
    return fetch(new URL(path, origin), {
      ...options, headers: { origin, ...(cookie ? { cookie } : {}), ...options.headers }, redirect: 'manual',
    });
  }
  const health = await request('/api/health');
  assert.equal(health.status, 200);
  assert.equal((await request('/api/migration?table=mat_stories')).status, 404);
  const photo = new Uint8Array([255, 216, 255, 224, 0, 2, 255, 217]);
  const reservationId = randomUUID();
  const upload = await request(`/api/migration?table=mat_reservations&photo=1&id=${reservationId}`, {
    method: 'POST', headers: { 'x-migration-token': migrationToken }, body: photo,
  });
  assert.equal(upload.status, 200);
  const uploaded = await upload.json();
  assert.equal(uploaded.sha256, createHash('sha256').update(photo).digest('hex'));
  const fixture = {id:reservationId,display_name:'HTTP fixture',phone:null,email:'test@example.test',reason:'rest',reason_other:'',
    title:'HTTP fixture',story:'Local verification only',photo:uploaded.key,payment_method:'deposit',amount:10000,
    source_story_id:null,story_id:null,created_at:new Date().toISOString()};
  const imported = await request('/api/migration?table=mat_reservations', {
    method:'POST',headers:{'x-migration-token':migrationToken,'content-type':'application/json'},body:JSON.stringify([fixture]),
  });
  assert.equal(imported.status,200);
  assert.equal((await request(`/api/admin/reservations/${reservationId}/photo`)).status,401);
  const login = await request('/api/admin/session', {method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({password})});
  assert.equal(login.status,200);
  cookie=login.headers.getSetCookie().map(value=>value.split(';')[0]).join('; ');
  assert.match(cookie,/mat_admin=/);
  const reservedPhoto=await request(`/api/admin/reservations/${reservationId}/photo`);
  assert.equal(reservedPhoto.status,200);
  assert.deepEqual(new Uint8Array(await reservedPhoto.arrayBuffer()),photo);
  function storyForm(revision) {
    const form=new FormData();
    for(const [key,value] of Object.entries({title:'HTTP fixture',matNumber:'9999',matSize:'small',displayName:'HTTP fixture',
      story:'Local verification only',paymentVerified:'true',published:'true',...(revision?{revision:String(revision)}:{reservationId})})) form.set(key,value);
    return form;
  }
  const created=await request('/api/admin/stories',{method:'POST',body:storyForm()});
  assert.equal(created.status,201);
  const {id}=await created.json();
  try {
    assert.equal((await request('/api/admin/stories',{method:'POST',body:storyForm()})).status,409);
    const publicPhoto=await request(`/api/stories/${id}/photo`);
    assert.equal(publicPhoto.status,200);
    assert.deepEqual(new Uint8Array(await publicPhoto.arrayBuffer()),photo);
    assert.equal((await request(`/api/admin/stories/${id}`,{method:'PUT',body:storyForm(1)})).status,200);
    assert.equal((await request(`/api/admin/stories/${id}`,{method:'PUT',body:storyForm(1)})).status,409);
    const deviceId=randomUUID();
    const react=()=>request(`/api/stories/${id}/reaction`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({deviceId,action:'react',kind:'like'})});
    const reactions=await Promise.all([react(),react(),react()]);
    for(const response of reactions)assert.equal(response.status,200);
    for(const result of await Promise.all(reactions.map(response=>response.json())))assert.equal(result.counts.like,1);
    const csv=await request('/api/admin/activity?format=csv');
    assert.equal(csv.status,200);assert.match(csv.headers.get('content-type'),/text\/csv/);
    assert.ok((await csv.text()).length>0);
    assert.equal((await request(`/api/admin/reservations/${reservationId}`,{method:'DELETE'})).status,200);
    assert.equal((await request(`/api/stories/${id}/photo`)).status,200);
    assert.equal((await request('/api/admin/session',{method:'DELETE'})).status,200);
    cookie='';
    assert.equal((await request('/api/admin/activity?format=csv')).status,401);
  } finally {
    const login=await request('/api/admin/session',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({password})});
    cookie=login.headers.getSetCookie().map(value=>value.split(';')[0]).join('; ');
    await request(`/api/admin/reservations/${reservationId}`,{method:'DELETE'});
    const deleted=await request(`/api/admin/stories/${id}`,{method:'DELETE',headers:{'content-type':'application/json'},body:JSON.stringify({revision:2})});
    assert.equal(deleted.status,200);
    assert.equal((await request(`/api/stories/${id}/photo`)).status,404);
  }
});
