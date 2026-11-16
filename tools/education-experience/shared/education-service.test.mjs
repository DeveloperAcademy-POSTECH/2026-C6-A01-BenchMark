import test from 'node:test';
import assert from 'node:assert/strict';
import {EducationService,validateDraft,validEducationPath,cardPaths,publicEducationStory} from './education-service.js';
const owner='e3780000-0000-4000-8000-000000000001',id='e3780000-0000-4000-8000-000000000011',snapshot='e3780000-0000-4000-8000-000000000021';
const draft={id,revision:0,display_name:'테스트 작성자',title:'가상 교육지구 이야기',body:'가상 자료입니다.',theme:'응원',emotion:'따뜻함'};
function fixture(){
 const calls=[];let row;
 const transport={identity:async()=>({id:owner,operator:false,canWrite:true}),
  async rpc(name,payload){calls.push({name,payload});
   if(name==='oi_education_mutate'){const p=payload.p_payload;row={...row,...p,origin:'education',storage_owner_id:owner,revision:p.revision+1,status:payload.p_action==='submit'?'pending':'draft'};return row;}
   if(name==='oi_education_story')return row;
   if(name==='oi_education_stories')return [];
  },async upload(path){calls.push({upload:path});},async media(path){calls.push({media:path});return 'https://kfzfzarslqdqmrazohej.supabase.co/storage/v1/object/sign/oi-story-media/'+path+'?token=synthetic';}};
 const s=new EducationService(transport);return {s,transport,calls};
}
test('education drafts omit all campus coordinates, placement and donation fields',()=>{
 const payload=validateDraft({...draft,latitude:36,longitude:129,grant_id:'synthetic'});
 assert.deepEqual(Object.keys(payload).sort(),['id','revision','display_name','title','body','theme','emotion'].sort());
 assert.equal(validateDraft({...draft,body:'가'.repeat(500)}).body.length,500);
 assert.throws(()=>validateDraft({...draft,body:'가'.repeat(501)}),/1,500/);
 assert.throws(()=>validateDraft({...draft,title:' '.repeat(3)}),/제목/);
 assert.throws(()=>validateDraft({...draft,theme:'not-a-theme'}),/테마/);
});
test('education storage and DTO contracts never accept campus content',()=>{
 const paths=cardPaths(owner,id,snapshot);assert.equal(paths.length,4);assert.ok(paths.every(validEducationPath));
 assert.equal(validEducationPath(`${owner}/${id}/card/${snapshot}.png`),false);
 assert.equal(validEducationPath(`${owner}/education/${id}/photos/../../secret.png`),false);
 assert.equal(publicEducationStory({origin:'education',status:'pending'}),null);
 assert.equal(publicEducationStory({origin:'campus',status:'published'}),null);
 assert.equal(publicEducationStory({...draft,origin:'education',status:'published',created_at:'2026-11-16T00:00:00Z'}).remote.id,id);
});
test('submission requires user consent, uploads all four immutable parts, then requests review',async()=>{
 const {s,calls}=fixture();await s.identity();let row=await s.save(draft);
 const parts=Array.from({length:4},()=>new Blob(['synthetic png'],{type:'image/png'})),photo=new Blob(['synthetic jpeg'],{type:'image/jpeg'});
 await assert.rejects(()=>s.submit(row,{photo,parts,snapshot,consented:false}),/공개 약관/);assert.equal(calls.filter(c=>c.upload).length,0);
 const receipts=[];row=await s.submit(row,{photo,parts,snapshot,consented:true,onReceipt:r=>receipts.push(r)});
 assert.equal(row.status,'pending');assert.equal(row.revision,3);assert.deepEqual(receipts.map(r=>r.revision),[2,3]);
 assert.equal(calls.filter(c=>c.upload).length,5);
 const submit=calls.findIndex(c=>c.payload?.p_action==='submit');assert.ok(calls.slice(0,submit).filter(c=>c.upload).length===5);
 assert.ok(calls.filter(c=>c.name).every(c=>c.name.startsWith('oi_education_')));
 assert.equal(calls[submit].payload.p_payload.publication_consent,true);
});
test('failed card upload preserves attached photo receipt and never submits a partial card',async()=>{
 const {s,transport,calls}=fixture();await s.identity();const row=await s.save(draft);let uploads=0,last;
 transport.upload=async()=>{if(++uploads===3)throw Error('upload failed');};
 await assert.rejects(()=>s.submit(row,{photo:new Blob(['photo'],{type:'image/jpeg'}),parts:Array.from({length:4},()=>new Blob(['png'],{type:'image/png'})),snapshot,consented:true,onReceipt:r=>last=r}),/upload failed/);
 assert.equal(last.revision,2);assert.equal(last.status,'draft');assert.ok(!calls.some(c=>c.payload?.p_action==='submit'));
});
test('lost save response is recovered only when revision and every saved field match',async()=>{
 const {s,transport}=fixture();await s.identity();const original=transport.rpc;
 transport.rpc=async(name,payload)=>{const value=await original(name,payload);if(name==='oi_education_mutate')throw Error('timeout');return value;};
 assert.equal((await s.save(draft)).revision,1);
 transport.rpc=async(name,payload)=>name==='oi_education_story'?{...draft,origin:'education',revision:1,status:'draft',body:'someone else changed this'}:Promise.reject(Error('timeout'));
 await assert.rejects(()=>s.save(draft),/timeout/);
});
test('account change discards delayed private URLs and stops uploads before attaching',async()=>{
 const {s,transport,calls}=fixture();await s.identity();let release;
 const path=cardPaths(owner,id,snapshot)[0];transport.media=()=>new Promise(r=>release=r);
 const image=s.media(path);s.reset();release('https://kfzfzarslqdqmrazohej.supabase.co/storage/v1/object/sign/x');await assert.rejects(()=>image,/계정/);assert.equal(s.mediaCache.size,0);
 await s.identity();const row=await s.save(draft);let unlock;transport.upload=()=>new Promise(r=>unlock=r);
 const pending=s.submit(row,{photo:new Blob(['photo'],{type:'image/jpeg'}),parts:Array.from({length:4},()=>new Blob(['png'],{type:'image/png'})),snapshot,consented:true});
 while(!unlock)await new Promise(r=>setTimeout(r,0));s.reset();unlock();await assert.rejects(()=>pending,/계정/);assert.ok(!calls.some(c=>c.payload?.p_action==='attach_media'));
});
test('public queries and mutation receipts fail closed',async()=>{
 const {s,transport}=fixture();
 await assert.rejects(()=>s.save(draft),/로그인/);
 transport.rpc=async()=>[{origin:'education',status:'draft'}];await assert.rejects(()=>s.list(),/공개된/);
 await s.identity();transport.rpc=async()=>({...draft,origin:'education',status:'draft',revision:12});await assert.rejects(()=>s.mutate('save',draft),/저장 결과/);
 await assert.rejects(()=>s.review({...draft,card_snapshot_id:snapshot},'published'),/운영자/);
});

test('draft photo decoding uses bytes rather than a CSP-blocked data URL request',async()=>{
 const {photoFromDataURL}=await import('./education-service.js');
 const photo=photoFromDataURL('data:image/jpeg;base64,c3ludGhldGlj');assert.equal(photo.type,'image/jpeg');assert.equal(await photo.text(),'synthetic');
 for(const value of ['https://example.com/photo.jpg','data:text/html;base64,c3ludGhldGlj','data:image/jpeg;base64,$bad'])assert.throws(()=>photoFromDataURL(value));
});
