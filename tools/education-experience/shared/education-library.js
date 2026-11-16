import {EducationService,publicEducationStory} from './education-service.js';
import {createNativeTransport} from './education-native-transport.js';
let service,pending,changing;
const emit=()=>window.dispatchEvent(new Event('education-stories-updated'));
export function sharedStoryForPearl(id){const rows=service?.publicRows;return rows?.length?publicEducationStory(rows[id%rows.length]):null;}
export function educationReady(){
 if(pending)return pending;
 pending=(async()=>{
  const native=!!window.webkit?.messageHandlers?.building;
  const transport=native?createNativeTransport():await (await import('./education-web-transport.js')).createWebTransport(authChanged);
  service=new EducationService(transport);await service.identity();await service.list();emit();return service;
 })().catch(error=>{pending=null;throw error;});
 return pending;
}
async function authChanged(){
 if(changing)return changing;
 changing=(async()=>{const s=await educationReady();s.reset();await s.identity();await s.list();emit();window.dispatchEvent(new Event('education-identity-updated'));})()
 .catch(()=>window.dispatchEvent(new Event('education-identity-updated'))).finally(()=>changing=null);
 return changing;
}
window.addEventListener('education-auth-changed',authChanged);
export async function refreshEducation(){const s=await educationReady();await s.list();emit();return s;}

// One view per selected story. No polling, image prefetch, or WebGL redraw is
// started by a card. Delayed results cannot replace a newer selected pearl.
export function mountEducationPreview(container,story,{privateStory=false}={}){
 const key=crypto.randomUUID();container.dataset.educationPreview=key;
 container.hidden=false;container.classList.remove('is-ready');
 const image=container.querySelector('img')??container.appendChild(document.createElement('img'));
 image.decoding='async';image.crossOrigin='anonymous';image.alt=story.title+' 카드 앞면';image.removeAttribute('src');
 container.querySelector('.education-card-controls')?.remove();
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
