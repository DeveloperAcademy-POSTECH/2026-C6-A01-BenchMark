const root=document.querySelector('.experience');
root.classList.add('web-viewer');
document.querySelector('.night-backdrop')?.remove();
document.querySelector('.space-mascot')?.remove();
const dimmer=document.createElement('div');dimmer.className='web-dimmer';dimmer.setAttribute('aria-hidden','true');root.prepend(dimmer);
const scatter=document.querySelector('#scatterButton');scatter.hidden=true;scatter.tabIndex=-1;scatter.setAttribute('aria-hidden','true');
const hint=document.createElement('span');hint.id='webGestureHint';hint.textContent='건물 클릭 · 드래그 회전 · 스크롤 확대';document.querySelector('.scene-bottom').append(hint);
const back=document.createElement('button');back.id='viewerReturn';back.type='button';back.hidden=true;
back.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m10 6-6 6 6 6M4 12h11a5 5 0 0 1 5 5"/></svg><span>건물로 돌아가기</span>';
root.append(back);
function restore(){if(root.classList.contains('is-scattered')&&document.querySelector('#building-stage').dataset.scatterTransition!=='gathering')scatter.click();}
back.addEventListener('click',restore);
const brand=document.querySelector('.brand');
brand.addEventListener('click',e=>{if(root.classList.contains('is-scattered')){e.preventDefault();restore();}});
function sync(){
 const active=root.classList.contains('is-scattered');back.hidden=!active;
 const canvas=document.querySelector('#building');if(canvas)canvas.setAttribute('role',active?'img':'button');
 brand.setAttribute('aria-label',active?'오이기부. 탭하면 건물로 돌아갑니다.':'오이기부 함께 짓는 캠퍼스 홈');
 const nav=document.querySelector('.garden-nav');nav.inert=active;nav.setAttribute('aria-hidden',String(active));
}
new MutationObserver(sync).observe(root,{attributes:true,attributeFilter:['class']});sync();
