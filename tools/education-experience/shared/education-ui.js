import {educationReady,refreshEducation,mountEducationPreview} from './education-library.js';
import {THEMES,EMOTIONS,validateDraft,photoFromDataURL,CONSENT_VERSION} from './education-service.js';
import {renderEducationCard} from './education-card.js';
const el=(tag,text,className)=>{const e=document.createElement(tag);if(text)e.textContent=text;if(className)e.className=className;return e;};
const button=(text,fn,className='education-button')=>{const e=el('button',text,className);e.type='button';e.addEventListener('click',fn);return e;};
const dialog=el('dialog',null,'education-dialog');dialog.id='educationDialog';
const close=button('×',()=>dialog.close(),'close-button');close.setAttribute('aria-label','닫기');close.dataset.close='';
const content=el('div',null,'education-content');dialog.append(close,content);document.body.append(dialog);
let viewGeneration=0,busy=false,writeTimer,persistCurrent=()=>{};
function shell(title,copy){persistCurrent();persistCurrent=()=>{};viewGeneration++;content.replaceChildren(el('p','빛으로 지은 이야기','education-kicker'),el('h2',title));if(copy)content.append(el('p',copy,'education-copy'));if(!dialog.open)dialog.showModal();return viewGeneration;}
dialog.addEventListener('close',()=>persistCurrent());
function status(text,error=false){let e=content.querySelector('.education-status');if(!e){e=el('p',null,'education-status');e.setAttribute('role','status');content.append(e);}e.textContent=text;e.classList.toggle('is-error',error);}
function fail(error){status(error?.message??'요청을 처리하지 못했어요. 다시 시도해 주세요.',true);}
function recordsKey(id){return 'oi-education-drafts-v1:'+id;}
function records(id){try{return JSON.parse(localStorage.getItem(recordsKey(id))??'{}');}catch{return {};}}
function storeDraft(account,draft,photoData){try{const all=records(account);all[draft.id]={draft,photoData,updated:Date.now()};localStorage.setItem(recordsKey(account),JSON.stringify(all));return true;}catch{return false;}}
function asBlob(data){return photoFromDataURL(data);}
async function normalizePhoto(file){
 if(!file.type.startsWith('image/')||file.size>25*1024*1024)throw Error('25MB 이하의 사진을 선택해 주세요.');
 const url=URL.createObjectURL(file),image=new Image();image.src=url;
 try{await image.decode();const scale=Math.min(1,1280/Math.max(image.naturalWidth,image.naturalHeight)),c=document.createElement('canvas');c.width=Math.max(1,Math.round(image.naturalWidth*scale));c.height=Math.max(1,Math.round(image.naturalHeight*scale));const ctx=c.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,c.width,c.height);ctx.drawImage(image,0,0,c.width,c.height);let data=c.toDataURL('image/jpeg',.8);if(data.length>1500000)data=c.toDataURL('image/jpeg',.65);if(data.length>1500000)throw Error('사진의 용량이 커요. 더 작은 사진을 선택해 주세요.');return data;}finally{URL.revokeObjectURL(url);}
}
async function requireIdentity(title){
 const s=await educationReady(),identity=await s.identity();
 if(identity.id)return s;
 shell(title,'앱과 같은 계정으로 로그인하면 앱과 웹의 교육지구 건물에서 같은 이야기를 볼 수 있어요.');
 const native=!!window.webkit?.messageHandlers?.building;
 for(const [provider,label] of native?[['native','앱 계정으로 로그인']]:[['google','Google로 로그인']])content.append(button(label,()=>s.transport.login(provider).catch(fail)));
 if(!native)content.append(el('p','앱에서 사용한 Google 계정으로 로그인해 주세요. Apple로 가입했다면 먼저 앱의 계정 설정에서 Google 로그인을 연결해 주세요.','education-copy'));
 content.append(el('p','작성에는 기부나 증빙 제출이 필요하지 않아요.','education-copy'));return null;
}
export async function openEducationWriter(existing=null){
 shell('나의 이야기 남기기','로그인 상태를 확인하고 있어요.');
 try{
  const s=await requireIdentity('나의 이야기 남기기');if(!s)return;
  const account=s.account.id,saved=records(account),cached=existing?saved[existing.id]:Object.values(saved).sort((a,b)=>b.updated-a.updated).find(r=>r.draft.status!=='pending'&&r.draft.status!=='published');
  let draft=existing?{...existing}:cached?.draft??{id:crypto.randomUUID(),revision:0,display_name:'',title:'',body:'',theme:'',emotion:'',status:'draft'};
  let photoData=cached?.photoData??null,photoBlob=null;
  const generation=shell('교육지구에 이야기 남기기','이 이야기는 교육지구 건물의 구슬에 남아요. 공개 검토를 통과하면 앱과 웹에서 함께 볼 수 있어요. 캠퍼스 지도에는 배치되지 않아요.');
  const form=el('form',null,'education-form');form.addEventListener('submit',e=>e.preventDefault());
  const input=(label,name,type='text')=>{const l=el('label',label),field=el(type==='textarea'?'textarea':'input');if(type!=='textarea')field.type=type;field.name=name;field.value=draft[name]??'';l.append(field);form.append(l);return field;};
  const select=(label,name,options)=>{const l=el('label',label),field=el('select');field.name=name;field.append(new Option('선택해 주세요',''),...options.map(v=>new Option(v,v)));field.value=draft[name]??'';l.append(field);form.append(l);return field;};
  select('테마 선택','theme',THEMES);select('감정 선택','emotion',EMOTIONS);
  const name=input('카드에 표시할 이름','display_name');name.maxLength=40;name.placeholder='이름을 공개하고 싶지 않다면 익명';
  const title=input('제목 · 45자 이내','title');title.maxLength=45;
  const message=input('이야기 · 1,500byte 이내','body','textarea');message.rows=5;
  const count=el('small',null,'education-counter');message.after(count);
  const photoLabel=el('label','이야기 사진 1장'),picker=el('input');picker.type='file';picker.accept='image/*';const preview=el('img');preview.className='education-photo-preview';preview.alt='카드에 넣을 사진';preview.hidden=!photoData;if(photoData)preview.src=photoData;
  photoLabel.append(picker,preview);form.append(photoLabel);
  const persist=()=>{if(s.account?.id!==account||generation!==viewGeneration)return;for(const field of form.elements)if(field.name)draft[field.name]=field.value;count.textContent=new TextEncoder().encode(message.value).length+' / 1,500byte';if(!storeDraft(account,draft,photoData))status('이 브라우저에 초안을 저장하지 못했어요. 서버 초안 저장을 이용해 주세요.',true);};
  persistCurrent=persist;
  form.addEventListener('input',()=>{clearTimeout(writeTimer);writeTimer=setTimeout(persist,250);});
  picker.addEventListener('change',async()=>{if(!picker.files[0])return;try{photoData=await normalizePhoto(picker.files[0]);if(generation!==viewGeneration)return;photoBlob=await asBlob(photoData);preview.src=photoData;preview.hidden=false;persist();}catch(error){fail(error);}});
  const consent=el('details'),summary=el('summary','공개 약관과 사진·글 사용 안내');consent.append(summary,el('p','실제 경험을 바탕으로 서로를 존중하는 이야기를 작성해 주세요. 연락처·주소·계좌번호 등 개인정보나 동의받지 않은 다른 사람의 사연은 넣지 말아 주세요. 본인이 작성했거나 사용 허락을 받은 사진과 글만 올려 주세요.'),el('p','등록한 이야기·사진·카드 양면은 운영자 검토를 거쳐 앱과 웹의 교육지구 구슬에 공개됩니다. 운영정책 위반이나 개인정보 노출이 있으면 공개가 제한될 수 있습니다. 기부 자료를 접수하거나 기부를 인증하는 절차가 아닙니다.'));
  const publication=el('input');publication.type='checkbox';const rights=el('input');rights.type='checkbox';
  const consentLabel=el('label',null,'education-check');consentLabel.append(publication,el('span','이야기·사진·카드의 앱·웹 공개와 운영자 검토에 동의합니다.'));
  const rightsLabel=el('label',null,'education-check');rightsLabel.append(rights,el('span','사진과 글의 사용 권한 및 포함된 인물의 동의를 확인했습니다.'));
  form.append(consent,consentLabel,rightsLabel,el('p','이 기기에 입력 내용을 자동 저장합니다. 서버 저장은 아래 버튼으로 진행해 주세요.','education-copy'));
  const actions=el('div',null,'education-actions');
  const save=button('서버에 초안 저장',()=>run(false)),submit=button('공개 검토 요청',()=>run(true),'education-button is-primary');actions.append(save,submit);form.append(actions);
  if(!s.account.canWrite){save.disabled=submit.disabled=true;status('지금은 이야기 접수를 잠시 쉬고 있어요. 저장한 초안은 그대로 남아 있어요.');}
  content.append(form,button('내 이야기 목록',()=>openEducationList('mine'),'education-text-button'));
  const legacy=(()=>{try{return JSON.parse(localStorage.getItem('postech-light-prototype-v1')??'null');}catch{return null;}})();
  if(!existing&&legacy?.message)content.append(button('이 브라우저의 기존 시연 이야기 가져오기',async()=>{draft={id:crypto.randomUUID(),revision:0,status:'draft',display_name:legacy.author??'',title:legacy.message.slice(0,30),body:legacy.message,theme:'응원',emotion:'따뜻함'};photoData=legacy.photo??null;storeDraft(account,draft,photoData);await openEducationWriter({...draft});},'education-text-button'));
  count.textContent=new TextEncoder().encode(message.value).length+' / 1,500byte';
  if(!photoData&&existing?.photo_paths?.[0])try{const url=await s.media(existing.photo_paths[0]),response=await fetch(url);if(!response.ok)throw Error('사진을 다시 선택해 주세요.');photoData=await normalizePhoto(await response.blob());if(generation===viewGeneration){photoBlob=await asBlob(photoData);preview.src=photoData;preview.hidden=false;persist();}}catch{status('기존 사진을 불러오지 못했어요. 사진을 다시 선택해 주세요.',true);}
  async function run(publish){
   if(busy)return;persist();
   try{
    validateDraft(draft);if(publish&&(!publication.checked||!rights.checked))throw Error('공개 약관과 사용 권한에 동의해 주세요.');
    if(publish&&!photoData)throw Error('이야기 사진을 한 장 선택해 주세요.');
    busy=true;save.disabled=submit.disabled=true;picker.disabled=true;
    status('초안을 저장하고 있어요.');
    if(draft.status&&draft.status!=='draft'){const edits=validateDraft(draft);draft={...await s.mutate('reopen',{id:draft.id,revision:draft.revision}),...edits,revision:draft.revision+1};}
    draft=await s.save(draft);storeDraft(account,draft,photoData);
    if(!publish&&photoData){status('사진을 초안에 보관하고 있어요.');photoBlob??=asBlob(photoData);draft=await s.attachPhoto(draft,photoBlob);storeDraft(account,draft,photoData);}
    if(publish){
     status('사진과 카드 양면을 준비하고 있어요.');photoBlob??=await asBlob(photoData);
     const bundle=await renderEducationCard(draft,photoBlob);
     draft=await s.submit(draft,{photo:photoBlob,...bundle,consented:true,onReceipt:row=>{draft=row;storeDraft(account,row,photoData);}});
    }
    if(generation!==viewGeneration)return;
    status(publish?'공개 검토를 요청했어요. 승인 후 앱과 웹의 교육지구 구슬에서 볼 수 있어요.':'서버에 초안을 저장했어요. 아직 다른 사람에게 공개되지 않았어요.');
    if(publish){form.querySelectorAll('input,textarea,select,button').forEach(e=>e.disabled=true);content.append(button('접수된 이야기 보기',()=>openEducationDetail(draft.id,true)));}
   }catch(error){if(generation===viewGeneration)fail(error);}
   finally{busy=false;if(generation===viewGeneration&&draft.status!=='pending'){save.disabled=submit.disabled=!s.account?.canWrite;picker.disabled=false;}}
  }
 }catch(error){fail(error);content.append(button('다시 연결',()=>openEducationWriter(existing)));}
}

export async function openEducationList(mode='public'){
 const generation=shell(mode==='mine'?'내 이야기':mode==='review'?'교육지구 공개 검토':'교육지구의 이야기','승인된 이야기는 앱과 웹의 같은 구슬 카드로 공유됩니다.');
 try{
  const s=mode==='public'?await educationReady():await requireIdentity(mode==='mine'?'내 이야기':'공개 검토');if(!s||generation!==viewGeneration)return;
  const nav=el('div',null,'education-actions');for(const [key,label] of [['public','공유 이야기'],['mine','내 이야기']])nav.append(button(label,()=>openEducationList(key),'education-text-button'));
  if(s.account?.operator)nav.append(button('공개 검토',()=>openEducationList('review'),'education-text-button'));
  nav.append(button('새로고침',()=>refreshEducation().then(()=>openEducationList(mode)).catch(fail),'education-text-button'));content.append(nav);
  const list=el('div',null,'education-story-list');content.append(list);let offset=0,loading=false;
  if(mode==='public'){
   for(const row of s.sharedRows.filter(row=>row.origin==='postech')){
    const item=button('',()=>openEducationReference(row.id),'education-list-item');item.append(el('small','POSTECH 공식 이야기 · '+row.author),el('strong',row.title),el('span',row.message.slice(0,100)));list.append(item);
   }
   list.append(el('h3','이용자가 남긴 이야기'));
  }
  const more=button('더 보기',load);content.append(more);
  async function load(){if(loading)return;loading=true;more.disabled=true;try{const rows=await s.list({offset,mine:mode==='mine',review:mode==='review'});if(generation!==viewGeneration)return;
   if(!offset&&!rows.length)list.append(el('p',mode==='public'?'아직 이용자가 공개한 이야기가 없어요. 첫 이야기를 남겨 주세요.':'아직 이야기가 없어요.','education-copy'));
   for(const row of rows){const b=button('',()=>openEducationDetail(row.id,mode!=='public',mode==='review'),'education-list-item');b.append(el('small',`${row.display_name} · ${({draft:'초안',pending:'검토 중',published:'공개 중',hidden:'비공개'})[row.status]}`),el('strong',row.title),el('span',row.body.slice(0,100)));list.append(b);}offset+=rows.length;more.hidden=rows.length<24;
  }catch(error){if(generation===viewGeneration)fail(error);}finally{loading=false;more.disabled=false;}}
  await load();
  if(s.account?.id){content.append(button('새 이야기 남기기',()=>openEducationWriter()));content.append(button('로그아웃',()=>s.transport.logout().catch(fail),'education-text-button'));}else content.append(button('로그인하고 이야기 남기기',()=>openEducationWriter()));
 }catch(error){fail(error);content.append(button('다시 연결',()=>openEducationList(mode)));}
}

export async function openEducationDetail(id,privateStory=false,review=false){
 const generation=shell('이야기를 불러오고 있어요');
 try{
  const s=await educationReady(),row=await s.story(id);if(generation!==viewGeneration)return;if(!row)throw Error('지금 볼 수 있는 이야기가 아니에요.');
  content.replaceChildren(el('p',row.theme+' · '+row.emotion,'education-kicker'),el('h2',row.title),el('p',row.display_name,'education-copy'));
  const figure=el('figure',null,'pearl-note-photo education-detail-photo');figure.append(el('img'),el('span','카드를 확인하고 있어요','pearl-note-photo-placeholder'));content.append(figure);
  if(row.card_snapshot_id)mountEducationPreview(figure,{...row,remote:row},{privateStory});else{figure.hidden=true;}
  content.append(el('p',row.body,'education-detail-body'),el('p',({draft:'서버에 저장된 초안입니다.',pending:'운영자 공개 검토를 기다리고 있어요.',published:'앱과 웹에 공개된 이야기입니다.',hidden:'현재 공개되지 않은 이야기입니다.'})[row.status],'education-copy'));
  if(privateStory&&!review)content.append(button(row.status==='published'?'공개를 중단하고 수정':'이야기 수정',async()=>{try{const draft=row.status==='draft'?row:await s.mutate('reopen',{id:row.id,revision:row.revision});await openEducationWriter(draft);}catch(error){fail(error);}}));
  if(privateStory&&!review)content.append(button('이야기 삭제',async()=>{try{await s.mutate('delete',{id:row.id,revision:row.revision});await openEducationList('mine');}catch(error){fail(error);}},'education-text-button'));
  if(review&&s.account?.operator){
   const area=el('div',null,'education-review-images'),approve=button('공개 승인',()=>decide('published'),'education-button is-primary');approve.disabled=true;
   const hide=button('비공개로 전환',()=>decide('hidden'));content.append(area,approve,hide);
   for(const report of row.reports??[])area.append(el('p',`신고: ${report.reason}\n${report.detail}`,'education-report-note'));
   try{for(let i=0;i<row.card_paths.length;i++){const image=el('img');image.alt=['앞면 원본','뒷면 원본','앞면 미리보기','뒷면 미리보기'][i];image.src=await s.media(row.card_paths[i]);area.append(image);await image.decode();}if(generation===viewGeneration)approve.disabled=false;}catch{status('필수 카드 이미지를 모두 불러오지 못해 공개 승인할 수 없어요.',true);}
   async function decide(value){if(busy)return;busy=true;approve.disabled=hide.disabled=true;try{await s.review(row,value);await refreshEducation();await openEducationList('review');}catch(error){fail(error);}finally{busy=false;hide.disabled=false;}}
  }
  if(row.status==='published'&&!review)content.append(button('이야기 신고',()=>showReport(s,row),'education-text-button'));
  content.append(button('목록으로',()=>openEducationList(review?'review':privateStory?'mine':'public'),'education-text-button'));
 }catch(error){fail(error);}
}
export async function openEducationReference(id){
 const generation=shell('공식 이야기를 불러오고 있어요');
 try{
  const s=await refreshEducation(),row=s.sharedRows.find(row=>row.id===id&&row.origin==='postech');
  if(generation!==viewGeneration)return;if(!row)throw Error('지금 볼 수 있는 이야기가 아니에요.');
  content.replaceChildren(el('p',row.kind+' · '+row.category,'education-kicker'),el('h2',row.title),el('p',row.author+' · '+row.affiliation,'education-copy'));
  const figure=el('figure',null,'pearl-note-photo education-detail-photo');figure.append(el('img'),el('span','사진을 불러오고 있어요','pearl-note-photo-placeholder'));content.append(figure);mountEducationPreview(figure,row);
  content.append(el('p',row.fund,'education-kicker'),el('p',row.message,'education-detail-body'),el('p','POSTECH 발전기금 · '+row.publishedAt+'\n원문 요약 · 사진 출처: POSTECH','education-copy'));
  const source=el('a','원문 읽기 ↗','education-button');source.href=row.sourceUrl;source.target='_blank';source.rel='noopener noreferrer';content.append(source,button('목록으로',()=>openEducationList()));
 }catch(error){fail(error);}
}
function showReport(s,row){
 shell('이야기 신고','신고 내용은 운영자만 확인할 수 있어요.');
 if(!s.account?.id){content.append(button('로그인',()=>s.transport.login('google').catch(fail)));return;}
 const reason=el('select');for(const [value,label] of [['privacy','개인정보 노출'],['abuse','비방·혐오'],['sexual','부적절한 성적 표현'],['violence','폭력적 내용'],['other','기타']])reason.append(new Option(label,value));
 const detail=el('textarea');detail.maxLength=1000;detail.rows=4;detail.setAttribute('aria-label','신고 설명');content.append(reason,detail,button('신고 접수',async()=>{try{await s.report(row.id,reason.value,detail.value);status('신고를 접수했어요.');}catch(error){fail(error);}}));
}
for(const id of ['writeButton','storiesButton'])document.querySelector('#'+id).addEventListener('click',event=>{event.preventDefault();event.stopImmediatePropagation();if(id==='writeButton')openEducationWriter();else openEducationList();},{capture:true});
window.addEventListener('education-open-story',event=>openEducationDetail(event.detail.id));
window.addEventListener('education-open-reference',event=>openEducationReference(event.detail.id));
window.addEventListener('education-identity-updated',()=>{if(dialog.open){busy=false;openEducationList('mine');}});
educationReady().catch(()=>{});
