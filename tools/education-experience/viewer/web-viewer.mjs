const root=document.querySelector('.experience');
root.classList.add('web-viewer');
document.querySelector('.night-backdrop')?.remove();
document.querySelector('.space-mascot')?.remove();
const dimmer=document.createElement('div');dimmer.className='web-dimmer';dimmer.setAttribute('aria-hidden','true');root.prepend(dimmer);
const scatter=document.querySelector('#scatterButton');scatter.hidden=true;scatter.tabIndex=-1;scatter.setAttribute('aria-hidden','true');
const hint=document.createElement('span');hint.id='webGestureHint';hint.textContent='건물 클릭 · 드래그 회전 · 스크롤 확대';document.querySelector('.scene-bottom').append(hint);
function restore(){if(root.classList.contains('is-scattered')&&document.querySelector('#building-stage').dataset.scatterTransition!=='gathering')scatter.click();}
const brand=document.querySelector('.brand');
brand.addEventListener('click',e=>{if(root.classList.contains('is-scattered')){e.preventDefault();restore();}});
function sync(){
 const active=root.classList.contains('is-scattered');
 const canvas=document.querySelector('#building');if(canvas){
  canvas.setAttribute('role','button');
  canvas.setAttribute('aria-label',active?'펼쳐진 진주빛 구슬. 클릭하거나 탭하면 건물로 돌아갑니다. 마우스를 올리면 이야기가 보이며 드래그로 회전할 수 있습니다.':'교육지구 2.0 건물. 탭하면 빛이 펼쳐집니다. 드래그로 회전하고 핀치로 확대할 수 있습니다.');
 }
 brand.setAttribute('aria-label',active?'오이기부. 탭하면 건물로 돌아갑니다.':'오이기부 함께 짓는 캠퍼스 홈');
 const nav=document.querySelector('.garden-nav');nav.inert=active;nav.setAttribute('aria-hidden',String(active));
}
new MutationObserver(sync).observe(root,{attributes:true,attributeFilter:['class']});sync();
