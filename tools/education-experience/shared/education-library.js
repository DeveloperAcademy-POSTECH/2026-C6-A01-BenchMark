import {EducationService} from './education-service.js';
import {createNativeTransport} from './education-native-transport.js';
let service,pending,changing,refreshing,lastRefresh=0,loadFailed=false;
const emit=()=>window.dispatchEvent(new Event('education-stories-updated'));
export function sharedStoryForPearl(id){
 const rows=service?.sharedRows;
 return rows?.length?rows[id%rows.length]:{id:'education-feed-status',origin:'system',category:'교육지구',title:'함께 나누는 이야기',author:'오이기부',message:loadFailed?'이야기 서버에 연결하지 못했어요. 이야기 둘러보기에서 다시 연결해 주세요.':'앱과 웹의 같은 이야기를 불러오고 있어요.',photo:null};
}
export function educationReady(){
 if(pending)return pending;
 pending=(async()=>{
  const native=!!window.webkit?.messageHandlers?.building;
  const transport=native?createNativeTransport():await (await import('./education-web-transport.js')).createWebTransport(authChanged);
  service=new EducationService(transport);await service.identity();await service.feed();lastRefresh=Date.now();loadFailed=false;emit();return service;
 })().catch(error=>{pending=null;loadFailed=true;emit();throw error;});
 return pending;
}
async function authChanged(){
 if(changing)return changing;
 changing=(async()=>{const s=await educationReady();s.reset();emit();await s.identity();await s.feed();lastRefresh=Date.now();loadFailed=false;emit();window.dispatchEvent(new Event('education-identity-updated'));})()
 .catch(()=>window.dispatchEvent(new Event('education-identity-updated'))).finally(()=>changing=null);
 return changing;
}
window.addEventListener('education-auth-changed',authChanged);
export function refreshEducation(){
 if(refreshing)return refreshing;
 refreshing=(async()=>{const s=await educationReady();await s.feed();lastRefresh=Date.now();loadFailed=false;emit();return s;})().finally(()=>refreshing=null);
 return refreshing;
}
function refreshWhenVisible(){
 if(document.hidden||window.__nativePaused||Date.now()-lastRefresh<=1000)return;
 educationReady().then(()=>{if(!document.hidden&&!window.__nativePaused&&Date.now()-lastRefresh>1000)return refreshEducation();}).catch(()=>{loadFailed=true;});
}
window.addEventListener('focus',refreshWhenVisible);
window.addEventListener('education-feed-refresh',refreshWhenVisible);
document.addEventListener('visibilitychange',refreshWhenVisible);
const experience=document.querySelector('.experience');let wasScattered=experience.classList.contains('is-scattered');
new MutationObserver(()=>{const active=experience.classList.contains('is-scattered');if(active&&!wasScattered)refreshWhenVisible();wasScattered=active;}).observe(experience,{attributes:true,attributeFilter:['class']});

// One view per selected story. No polling, image prefetch, or WebGL redraw is
// started by a card. Delayed results cannot replace a newer selected pearl.
export function mountEducationPreview(container,story,{privateStory=false}={}){
 const key=crypto.randomUUID();container.dataset.educationPreview=key;
 container.hidden=false;container.classList.remove('is-ready');
 const image=container.querySelector('img')??container.appendChild(document.createElement('img'));
 image.decoding='async';image.crossOrigin='anonymous';image.alt=story.title+' 카드 앞면';image.removeAttribute('src');
 container.querySelector('.education-card-controls')?.remove();
 if(story.origin==='postech'){
  container.classList.add('education-reference-photo');image.alt=story.photoAlt;
  const timer=setTimeout(async()=>{try{if(container.dataset.educationPreview!==key)return;image.src=story.photo;await image.decode();if(container.dataset.educationPreview===key)container.classList.add('is-ready');}catch{const placeholder=container.querySelector('.pearl-note-photo-placeholder');if(placeholder)placeholder.textContent='사진을 불러오지 못했어요';}},140);
  return ()=>{clearTimeout(timer);if(container.dataset.educationPreview===key){delete container.dataset.educationPreview;image.removeAttribute('src');}};
 }
 container.classList.remove('education-reference-photo');
 const controls=document.createElement('div');controls.className='education-card-controls';
 const front=document.createElement('button'),back=document.createElement('button');front.type=back.type='button';front.textContent='앞면';back.textContent='뒷면';
 controls.append(front,back);container.append(controls);
 const placeholder=container.querySelector('.pearl-note-photo-placeholder');if(placeholder)placeholder.textContent='카드를 확인하고 있어요';
 let row,side=0;
 const current=()=>container.dataset.educationPreview===key;
 async function show(index){
  if(!row)return;side=index;container.classList.remove('is-ready');front.setAttribute('aria-pressed',String(index===0));back.setAttribute('aria-pressed',String(index===1));
  try{
   const s=await educationReady(),url=await s.media(row.card_paths[index+2]);
   if(!current()||side!==index)return;image.alt=row.title+' 카드 '+(index?'뒷면':'앞면');image.src=url;await image.decode();
   if(current()&&side===index)container.classList.add('is-ready');
  }catch{if(current()&&placeholder)placeholder.textContent='카드를 불러오지 못했어요. 다시 선택해 주세요.';}
 }
 front.addEventListener('click',()=>show(0));back.addEventListener('click',()=>show(1));
 const timer=setTimeout(()=>{(async()=>{
  if(!current())return;const s=await educationReady();if(!current())return;row=await s.story(story.id);if(!current())return;
  if(!row||(!privateStory&&row.status!=='published')||!Array.isArray(row.card_paths)||row.card_paths.length!==4)throw Error('Story unavailable');
  await show(0);
 })().catch(()=>{if(current()){container.classList.remove('is-ready');if(placeholder)placeholder.textContent='지금 공개된 이야기가 아니에요.';}});},140);
 return ()=>{clearTimeout(timer);if(current()){delete container.dataset.educationPreview;image.removeAttribute('src');}};
}
window.educationMountPreview=mountEducationPreview;
