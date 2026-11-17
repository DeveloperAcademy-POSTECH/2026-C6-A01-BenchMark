import test from 'node:test';
import assert from 'node:assert/strict';
import {EducationService,validateDraft,validEducationPath,cardPaths,publicEducationStory,REFERENCE_ROOT,referenceStory,fetchReferenceCatalog} from './education-service.js';
const owner='e3780000-0000-4000-8000-000000000001',id='e3780000-0000-4000-8000-000000000011',snapshot='e3780000-0000-4000-8000-000000000021';
const draft={id,revision:0,display_name:'테스트 작성자',title:'가상 교육지구 이야기',body:'가상 자료입니다.',theme:'응원',emotion:'따뜻함'};
function fixture(){
 const calls=[];let row;
 const transport={identity:async()=>({id:owner,operator:false,canWrite:true}),catalog:async()=>[],
  async rpc(name,payload){calls.push({name,payload});
   if(name==='oi_education_mutate'){const p=payload.p_payload;row={...row,...p,origin:'education',storage_owner_id:owner,revision:p.revision+1,review_ready:payload.p_action==='submit',status:payload.p_action==='submit'?'pending':'draft'};return row;}
   if(name==='oi_education_story')return row;
   if(name==='oi_education_stories')return [];
  },async moderate(id,revision){
   calls.push({moderate:{id,revision}});
   row={...row,revision:revision+1,status:'published',review_ready:false};
   return {status:'approved',story_id:id,revision:row.revision,story:row};
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
 assert.equal('reports' in publicEducationStory({...draft,origin:'education',status:'published',reports:[{reason:'synthetic'}]}).remote,false);
});
test('submission requires user consent, uploads all four immutable parts, then requests review',async()=>{
 const {s,calls}=fixture();await s.identity();let row=await s.save(draft);
 const parts=Array.from({length:4},()=>new Blob(['synthetic png'],{type:'image/png'})),photo=new Blob(['synthetic jpeg'],{type:'image/jpeg'});
 await assert.rejects(()=>s.submit(row,{photo,parts,snapshot,consented:false}),/공개 약관/);assert.equal(calls.filter(c=>c.upload).length,0);
 const receipts=[];row=await s.submit(row,{photo,parts,snapshot,consented:true,onReceipt:r=>receipts.push(r)});
 assert.equal(row.status,'published');assert.equal(row.revision,4);assert.deepEqual(receipts.map(r=>r.revision),[2,3,4]);
 assert.equal(calls.filter(c=>c.upload).length,5);
 const submit=calls.findIndex(c=>c.payload?.p_action==='submit');assert.ok(calls.slice(0,submit).filter(c=>c.upload).length===5);
 assert.ok(calls.filter(c=>c.name).every(c=>c.name.startsWith('oi_education_')));
 assert.equal(calls[submit].payload.p_payload.publication_consent,true);
 assert.equal(calls[submit].payload.p_payload.ai_review_consent_version,1);
 assert.deepEqual(calls.at(-1),{moderate:{id,revision:3}});
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
 await assert.rejects(()=>s.hide({...draft,card_snapshot_id:snapshot,status:'published'}),/운영자/);
});

test('draft photo decoding uses bytes rather than a CSP-blocked data URL request',async()=>{
 const {photoFromDataURL}=await import('./education-service.js');
 const photo=photoFromDataURL('data:image/jpeg;base64,c3ludGhldGlj');assert.equal(photo.type,'image/jpeg');assert.equal(await photo.text(),'synthetic');
 for(const value of ['https://example.com/photo.jpg','data:text/html;base64,c3ludGhldGlj','data:image/jpeg;base64,$bad'])assert.throws(()=>photoFromDataURL(value));
});

const reference={id:'postech-900001',origin:'postech',kind:'Synthetic reference',category:'Synthetic',title:'Synthetic title',author:'Synthetic author',affiliation:'Synthetic affiliation',fund:'Synthetic fund',message:'Synthetic reference body',photo:REFERENCE_ROOT+'postech-900001/'+'a'.repeat(64)+'.webp',photoAlt:'Synthetic portrait',sourceUrl:'https://vision.postech.ac.kr/web/?top=support&sub=story&key=detail&code=900001',sourceTitle:'Synthetic source',publishedAt:'2026-11-16',isSummary:true};
test('app and web feeds combine the same references and reviewed user cards',async()=>{
 const a=fixture(),b=fixture();let published=[];
 for(const item of [a,b]){item.transport.catalog=async()=>[reference];item.transport.rpc=async(name)=>name==='oi_education_stories'?published:undefined;}
 assert.deepEqual(await a.s.feed(),await b.s.feed());assert.equal(a.s.sharedRows.length,1);
 published=[{...draft,origin:'education',status:'published',created_at:'2026-11-16T00:00:00Z',card_paths:cardPaths(owner,id,snapshot)}];
 assert.deepEqual(await a.s.feed(),await b.s.feed());assert.equal(a.s.sharedRows.length,2);assert.deepEqual(a.s.sharedRows[1].remote.card_paths,cardPaths(owner,id,snapshot));
 a.transport.rpc=async()=>[{...published[0],id:owner}];await a.s.list({offset:24});assert.deepEqual(a.s.sharedRows,b.s.sharedRows,'List pagination must not change the per-pearl feed');
 published=[{...published[0],status:'pending'}];await assert.rejects(()=>b.s.feed(),/공개된/);
});
test('reference catalog is read from the shared server and rejects duplicate or foreign sources',async()=>{
 let requested;
 const rows=await fetchReferenceCatalog(async(url,options)=>{requested={url,options};return Response.json({version:1,stories:[reference]});});
 assert.equal(requested.url,REFERENCE_ROOT+'catalog-v1.json');assert.equal(requested.options.cache,'no-cache');assert.deepEqual(rows,[reference]);
 for(const photo of ['https://example.com/photo.webp',REFERENCE_ROOT+'postech-900001/../'+'a'.repeat(64)+'.webp'])assert.throws(()=>referenceStory({...reference,photo}));
 assert.throws(()=>referenceStory({...reference,sourceUrl:'https://example.com'}));
 await assert.rejects(()=>fetchReferenceCatalog(async()=>Response.json({version:1,stories:[reference,reference]})),/중복/);
});
test('account change discards an old shared feed response',async()=>{
 const {s,transport}=fixture();let release;
 transport.catalog=()=>new Promise(resolve=>release=resolve);const pending=s.feed();s.reset();release([reference]);
 await assert.rejects(()=>pending,/계정/);assert.deepEqual(s.sharedRows,[]);
});
test('shared feed reads all public pages without silently dropping older cards',async()=>{
 const {s,transport,calls}=fixture();
 const stories=Array.from({length:51},(_,i)=>({...draft,id:crypto.randomUUID(),origin:'education',status:'published',created_at:'2026-11-16T00:00:00Z'}));
 transport.catalog=async()=>[reference];transport.rpc=async(name,payload)=>{calls.push({name,payload});return stories.slice(payload.p_offset,payload.p_offset+payload.p_limit);};
 const rows=await s.feed();assert.equal(rows.length,52);assert.deepEqual(calls.map(c=>c.payload.p_offset),[0,50]);assert.equal(rows.at(-1).id,stories.at(-1).id);
});

test('an interrupted review preserves the pending revision, then recovers a committed result',async()=>{
 const {s,transport}=fixture();await s.identity();const saved=await s.save(draft);
 const realModerate=transport.moderate;transport.moderate=async()=>{throw Error('timeout');};
 const receipts=[];
 await assert.rejects(()=>s.submit(saved,{photo:new Blob(['photo'],{type:'image/jpeg'}),
  parts:Array.from({length:4},()=>new Blob(['png'],{type:'image/png'})),snapshot,consented:true,
  onReceipt:r=>receipts.push({...r})}),/완료하지 못했어요/);
 assert.equal(receipts.at(-1).status,'pending');
 transport.moderate=async(...args)=>{await realModerate(...args);throw Error('lost response');};
 assert.equal((await s.moderate(receipts.at(-1))).status,'published');
});
