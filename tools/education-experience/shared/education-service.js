export const THEMES=['가족','우정','사랑','성장','도전','꿈','배움','경쟁','협력','갈등','화해','일탈','나눔','응원','성취','기타'];
export const EMOTIONS=['행복함','즐거움','뿌듯함','고마움','편안함','설렘','따뜻함','짜릿함','놀라움','신남','벅참','그리움','후련함','부끄러움','후회','긴장감','슬픔','화남','아쉬움','기타'];
export const CONSENT_VERSION='education-v2-2026-11-17';
export const REFERENCE_ROOT='https://kfzfzarslqdqmrazohej.supabase.co/storage/v1/object/public/oi-education-reference/';
export function referenceStory(row){
 if(!row||!/^postech-\d{1,9}$/.test(row.id)||row.origin!=='postech'||row.isSummary!==true)throw Error('공식 이야기 정보를 확인하지 못했어요.');
 for(const key of ['title','author','kind','category','affiliation','fund','message','photoAlt','sourceTitle','publishedAt'])if(typeof row[key]!=='string'||!row[key].trim())throw Error('공식 이야기 항목이 올바르지 않아요.');
 const code=row.id.slice(8),source=`https://vision.postech.ac.kr/web/?top=support&sub=story&key=detail&code=${code}`;
 const prefix=REFERENCE_ROOT+row.id+'/';
 if(row.sourceUrl!==source||!/^\d{4}-\d{2}-\d{2}$/.test(row.publishedAt)||!row.photo?.startsWith(prefix)||!/^[a-f0-9]{64}\.webp$/.test(row.photo.slice(prefix.length)))throw Error('공식 이야기 출처와 사진 주소를 확인하지 못했어요.');
 return Object.fromEntries(['id','origin','kind','category','title','author','affiliation','fund','message','photo','photoAlt','sourceUrl','sourceTitle','publishedAt','isSummary'].map(key=>[key,row[key]]));
}
export async function fetchReferenceCatalog(fetcher=globalThis.fetch){
 const response=await fetcher(REFERENCE_ROOT+'catalog-v1.json',{cache:'no-cache'});
 if(!response.ok)throw Error('공식 이야기를 불러오지 못했어요. 다시 연결해 주세요.');
 const data=await response.json();
 if(data.version!==1||!Array.isArray(data.stories)||data.stories.length>50)throw Error('공식 이야기 목록이 올바르지 않아요.');
 const rows=data.stories.map(referenceStory);
 if(new Set(rows.map(row=>row.id)).size!==rows.length)throw Error('공식 이야기가 중복되어 있어요.');
 return rows;
}
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export function validEducationPath(path){
 if(typeof path!=='string'||path.includes('..'))return false;
 const p=path.split('/');
 return uuid.test(p[0])&&p[1]==='education'&&uuid.test(p[2])&&(
  (p.length===5&&p[3]==='photos'&&/^[0-9a-f-]{36}\.(jpg|png)$/.test(p[4]))||
  (p.length===5&&p[3]==='card'&&/^[0-9a-f-]{36}\.png$/.test(p[4]))||
  (p.length===6&&p[3]==='card'&&uuid.test(p[4])&&['back.png','front-preview.png','back-preview.png'].includes(p[5])));
}
export function cardPaths(owner,id,snapshot){
 if(![owner,id,snapshot].every(v=>uuid.test(v)))throw Error('카드 식별자를 확인하지 못했어요.');
 const base=`${owner}/education/${id}/card/${snapshot}`;
 return [base+'.png',base+'/back.png',base+'/front-preview.png',base+'/back-preview.png'];
}
export function validateDraft(draft){
 if(!uuid.test(draft.id)||!Number.isInteger(draft.revision)||draft.revision<0)throw Error('초안을 다시 열어 주세요.');
 if(!draft.display_name?.trim()||[...draft.display_name.trim()].length>40)throw Error('공개 이름은 40자 이내로 입력해 주세요.');
 if(!draft.title?.trim()||[...draft.title.trim()].length>45)throw Error('제목은 45자 이내로 입력해 주세요.');
 if(!draft.body?.trim()||new TextEncoder().encode(draft.body).length>1500)throw Error('이야기는 1,500byte 이내로 입력해 주세요.');
 if(!THEMES.includes(draft.theme)||!EMOTIONS.includes(draft.emotion))throw Error('테마와 감정을 선택해 주세요.');
 return {id:draft.id,revision:draft.revision,display_name:draft.display_name.trim(),title:draft.title.trim(),body:draft.body.trim(),theme:draft.theme,emotion:draft.emotion};
}
export function publicEducationStory(row){
 if(!row||row.origin!=='education'||row.status!=='published')return null;
 const {reports,review_reason,review_source,review_ready,...publicRow}=row;
 return {id:row.id,origin:'education',kind:'교육지구 이야기',category:row.theme,title:row.title,author:row.display_name,message:row.body,
  fund:'빛으로 지은 이야기',photo:null,photoAlt:row.title+' 카드 앞면',publishedAt:row.created_at?.slice(0,10),remote:publicRow};
}

export class EducationService{
 constructor(transport){this.transport=transport;this.generation=0;this.account=null;this.mediaCache=new Map();this.publicRows=[];this.sharedRows=[];}
 reset(){this.generation++;this.account=null;this.mediaCache.clear();this.publicRows=[];this.sharedRows=[];}
 async feed(){
  const generation=this.generation;
  const readPublished=async()=>{
   const rows=[];
   for(let offset=0;offset<=10000;offset+=50){
    const page=await this.rpc('oi_education_stories',{p_offset:offset,p_limit:50,p_mine:false,p_review:false});
    if(!Array.isArray(page)||page.length>50||page.some(row=>!publicEducationStory(row)))throw Error('공개된 교육지구 이야기만 볼 수 있어요.');
    rows.push(...page);if(page.length<50)return [...new Map(rows.map(row=>[row.id,row])).values()];
   }
   throw Error('이야기 목록이 커서 모두 확인하지 못했어요. 다시 연결해 주세요.');
  };
  const [catalog,stories]=await Promise.all([this.transport.catalog(),readPublished()]);
  if(generation!==this.generation)throw Error('계정이 바뀌었어요. 다시 연결해 주세요.');
  if(!Array.isArray(stories)||stories.some(row=>!publicEducationStory(row)))throw Error('공개된 교육지구 이야기만 볼 수 있어요.');
  this.sharedRows=[...catalog.map(referenceStory),...stories.map(publicEducationStory)];
  return this.sharedRows;
 }
 async identity(){const generation=this.generation;const value=await this.transport.identity();if(generation!==this.generation)throw Error('계정이 바뀌었어요. 다시 시도해 주세요.');this.account=value;return value;}
 async rpc(name,payload={}){const generation=this.generation;const value=await this.transport.rpc(name,payload);if(generation!==this.generation)throw Error('계정이 바뀌었어요. 다시 시도해 주세요.');return value;}
 async list({offset=0,mine=false,review=false}={}){
  const rows=await this.rpc('oi_education_stories',{p_offset:offset,p_limit:24,p_mine:mine,p_review:review});
  if(!Array.isArray(rows))throw Error('이야기 목록을 확인하지 못했어요.');
  if(!mine&&!review){if(rows.some(row=>row.origin!=='education'||row.status!=='published'))throw Error('공개된 교육지구 이야기만 볼 수 있어요.');
   this.publicRows=offset?[...new Map([...this.publicRows,...rows].map(row=>[row.id,row])).values()]:rows;
  }
  return rows;
 }
 async story(id){if(!uuid.test(id))throw Error('이야기 식별자가 올바르지 않아요.');return this.rpc('oi_education_story',{p_id:id});}
 async mutate(action,payload){
  if(!this.account?.id)throw Error('앱과 같은 계정으로 로그인해 주세요.');
  if(!['save','attach_media','submit','reopen','delete','review'].includes(action))throw Error('지원하지 않는 요청이에요.');
  const receipt=await this.rpc('oi_education_mutate',{p_action:action,p_payload:payload});
  if(!receipt||receipt.id!==payload.id||receipt.origin!=='education'||receipt.revision!==payload.revision+1)throw Error('저장 결과를 확인하지 못했어요. 목록에서 최신 상태를 확인해 주세요.');
  return receipt;
 }
 async save(draft){
  const payload=validateDraft(draft);
  try{return await this.mutate('save',payload);}catch(error){
   const current=await this.story(payload.id).catch(()=>null);
   if(current?.status==='draft'&&current.revision===payload.revision+1&&['display_name','title','body','theme','emotion'].every(k=>current[k]===payload[k]))return current;
   throw error;
  }
 }
 async upload(path,blob){
  if(!this.account?.id||!validEducationPath(path)||!(blob instanceof Blob)||blob.size<1||blob.size>8388608||!['image/png','image/jpeg'].includes(blob.type))throw Error('이미지와 로그인 상태를 확인해 주세요.');
  const generation=this.generation;await this.transport.upload(path,blob);if(generation!==this.generation)throw Error('계정이 바뀌었어요. 다시 로그인해 주세요.');
 }
 async media(path){
  if(!validEducationPath(path))throw Error('교육지구 이미지 경로가 올바르지 않아요.');
  const previous=this.mediaCache.get(path);if(previous&&previous.until>Date.now())return previous.value;
  const generation=this.generation,value=await this.transport.media(path);
  if(generation!==this.generation)throw Error('계정이 바뀌었어요.');
  const url=new URL(value);if(url.protocol!=='https:'||url.hostname!=='kfzfzarslqdqmrazohej.supabase.co')throw Error('이미지 주소를 확인하지 못했어요.');
  this.mediaCache.set(path,{value,until:Date.now()+180000});return value;
 }
 async attachPhoto(story,photo){
  const owner=story.storage_owner_id;
  const data=new Uint8Array(await photo.arrayBuffer()),digest=new Uint8Array(await crypto.subtle.digest('SHA-256',data));
  const photoID=uuidFromBytes(digest),photoPath=`${owner}/education/${story.id}/photos/${photoID}.${photo.type==='image/png'?'png':'jpg'}`;
  await this.upload(photoPath,photo);
  return this.mutate('attach_media',{id:story.id,revision:story.revision,paths:[photoPath]});
 }
 async submit(story,{photo,parts,snapshot,consented,onReceipt=()=>{}}){
  if(!consented)throw Error('공개 약관과 사진·글 사용 권한을 확인해 주세요.');
  if(story.status!=='draft'||!photo||!Array.isArray(parts)||parts.length!==4)throw Error('초안과 카드 양면을 확인해 주세요.');
  const generation=this.generation,owner=story.storage_owner_id;
  let saved=await this.attachPhoto(story,photo);onReceipt(saved);
  const paths=cardPaths(owner,story.id,snapshot);
  for(let i=0;i<4;i++){if(this.generation!==generation)throw Error('계정이 바뀌었어요.');await this.upload(paths[i],parts[i]);}
  try{
   saved=await this.mutate('submit',{id:saved.id,revision:saved.revision,card_snapshot_id:snapshot,publication_consent:true,rights_consent:true,ai_review_consent_version:1,consent_version:CONSENT_VERSION});
  }catch(error){
   const current=await this.story(saved.id).catch(()=>null);
   if(current?.review_ready===true&&current.revision===saved.revision+1&&current.card_snapshot_id===snapshot)saved=current;else throw error;
  }
  onReceipt(saved);
  const reviewed=await this.moderate(saved);
  onReceipt(reviewed);
  return reviewed;
 }
 async moderate(story){
  if(!this.account?.id||story.status!=='pending'||story.review_ready!==true||!uuid.test(story.id))throw Error('내 이야기에서 최신 검토 상태를 확인해 주세요.');
  const generation=this.generation;
  const confirms=row=>row?.origin==='education'&&row.id===story.id&&row.revision===story.revision+1&&row.card_snapshot_id===story.card_snapshot_id&&
   (row.status==='published'||(row.status==='pending'&&typeof row.review_reason==='string'&&row.review_ready===false));
  try{
   const result=await this.transport.moderate(story.id,story.revision);
   if(generation!==this.generation)throw Error('계정이 바뀌었어요.');
   if(result?.story_id===story.id&&result.revision===story.revision+1&&confirms(result.story)&&
      result.status===(result.story.status==='published'?'approved':'rejected'))return result.story;
   throw Error('자동검수 결과를 확인하지 못했어요.');
  }catch(error){
   if(generation!==this.generation)throw error;
   const current=await this.story(story.id).catch(()=>null);
   if(generation!==this.generation)throw Error('계정이 바뀌었어요.');
   if(confirms(current))return current;
   throw Error('자동검수를 완료하지 못했어요. 내 이야기에서 다시 시도해 주세요.');
  }
 }
 async hide(story){
  if(!this.account?.operator||story.status!=='published')throw Error('운영자 권한과 현재 공개 상태를 확인해 주세요.');
  return this.mutate('review',{id:story.id,revision:story.revision,status:'hidden',card_snapshot_id:story.card_snapshot_id});
 }
 async report(id,reason,detail=''){if(!this.account?.id)throw Error('신고하려면 로그인해 주세요.');return this.rpc('oi_education_report',{p_story:id,p_reason:reason,p_detail:detail});}
}
export function uuidFromBytes(bytes){const b=Uint8Array.from(bytes.slice(0,16));b[6]=(b[6]&15)|80;b[8]=(b[8]&63)|128;const s=[...b].map(v=>v.toString(16).padStart(2,'0')).join('');return `${s.slice(0,8)}-${s.slice(8,12)}-${s.slice(12,16)}-${s.slice(16,20)}-${s.slice(20)}`;}

export function photoFromDataURL(value){
 const match=typeof value==='string'&&value.length<=1600000&&value.match(/^data:(image\/(?:jpeg|png));base64,([A-Za-z0-9+/=]+)$/);
 if(!match)throw Error('사진을 다시 선택해 주세요.');
 const bytes=Uint8Array.from(atob(match[2]),c=>c.charCodeAt(0));return new Blob([bytes],{type:match[1]});
}
