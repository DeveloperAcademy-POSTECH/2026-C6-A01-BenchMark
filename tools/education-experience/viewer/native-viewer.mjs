const root = document.querySelector('.experience');
root.classList.add('native-viewer');
root.dataset.viewerLayout = 'aim-story-split-v1';
document.querySelector('.garden-notes')?.remove();
document.querySelector('.night-backdrop')?.remove();
document.querySelector('.space-mascot')?.remove();
const dimmer=document.createElement('div');dimmer.className='viewer-dimmer';dimmer.setAttribute('aria-hidden','true');root.prepend(dimmer);
const intro = document.querySelector('.intro');
intro.append(document.querySelector('.funding'));

const symbol = (name) => ({
  more:'<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="12" r="1.8"/><circle cx="12" cy="12" r="1.8"/><circle cx="19" cy="12" r="1.8"/></svg>',
  close:'<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m6 6 12 12M18 6 6 18"/></svg>'
})[name];
const controls = document.createElement('div'); controls.className = 'viewer-header-controls';
controls.innerHTML = `<button id="viewerMenuButton" popovertarget="viewerMenu" aria-label="보기 메뉴" aria-expanded="false">${symbol('more')}</button><button id="viewerClose" aria-label="체험 닫기">${symbol('close')}</button>`;
document.querySelector('.masthead').append(controls);
const menu = document.createElement('div'); menu.id = 'viewerMenu'; menu.popover = 'auto'; menu.setAttribute('aria-label','보기 메뉴');
menu.innerHTML = '<button id="viewerScatter">빛 펼치기</button><div class="viewer-menu-divider"></div>';
menu.append(document.querySelector('.view-controls'));
const about = document.createElement('button'); about.textContent = '교육지구 안내'; about.addEventListener('click',() => document.querySelector('#aboutButton').click()); menu.append(about);
root.append(menu);
menu.addEventListener('toggle',e => document.querySelector('#viewerMenuButton').setAttribute('aria-expanded',String(e.newState === 'open')));
menu.addEventListener('click',e => { if (e.target.closest('button')) menu.hidePopover(); });
const scatter = document.querySelector('#scatterButton'); scatter.hidden = true;
document.querySelector('#viewerScatter').addEventListener('click',() => scatter.click());
function returnToBuilding(){
  if(root.classList.contains('is-scattered')&&document.querySelector('#building-stage').dataset.scatterTransition!=='gathering')scatter.click();
}
window.educationReturnToBuilding=returnToBuilding;
const aim=document.createElement('div');aim.id='viewerAim';aim.setAttribute('aria-hidden','true');aim.innerHTML='<span></span>';
const story=document.createElement('section');story.id='viewerAimStory';story.setAttribute('aria-label','에임으로 선택한 이야기');
story.innerHTML='<p class="aim-story-kicker">빛으로 지은 이야기</p><figure id="viewerAimPhoto" class="education-aim-preview aim-story-photo" hidden><img decoding="async" alt=""><span class="pearl-note-photo-placeholder">사진을 불러오는 중</span><button type="button">이야기 자세히 보기</button></figure><div class="aim-story-content" role="status" aria-live="polite" aria-atomic="true"><p class="aim-story-category"></p><p class="aim-story-message"></p><p class="aim-story-author"></p><p class="aim-story-source"></p></div><p class="aim-story-help">드래그해 이야기 찾기 · 아래 구슬을 탭해 건물로 돌아가기</p>';
root.append(aim,story);
document.querySelector('#viewerClose').addEventListener('click',() => window.webkit?.messageHandlers?.building?.postMessage({kind:'close'}));

const hint = document.createElement('div'); hint.id = 'viewerGestureHint'; hint.innerHTML = '<strong>탭하여 빛 펼치기</strong><span>드래그 회전 · 핀치 확대</span>'; root.append(hint);
const write = document.querySelector('#writeButton'); write.replaceChildren(document.createTextNode('나의 이야기 남기기'));
document.querySelector('#storiesButton').replaceChildren(document.createTextNode('이야기 둘러보기'));

let previous;
const brand=document.querySelector('.brand');
brand.addEventListener('click',e=>{if(root.classList.contains('is-scattered')){e.preventDefault();returnToBuilding();}});
function syncAppearance() {
  const active = root.classList.contains('is-scattered');
  document.querySelector('.viewer-header-controls').inert=active;
  hint.inert=active;
  if(active&&menu.matches(':popover-open'))menu.hidePopover();
  brand.setAttribute('aria-label',active?'오이기부. 탭하면 건물로 돌아갑니다.':'오이기부 함께 짓는 캠퍼스 홈');
  hint.querySelector('strong').textContent = active ? '빛을 탭하여 이야기 보기' : '탭하여 빛 펼치기';
  document.querySelector('#viewerScatter').textContent = active ? '건물로 모으기' : '빛 펼치기';
  const directions = document.querySelector('.view-controls'); directions.inert = false; directions.removeAttribute('aria-hidden');
  const canvas = document.querySelector('#building');
  if (canvas) { canvas.setAttribute('role','button');canvas.setAttribute('aria-label',active?'펼쳐진 구슬. 드래그하면 가운데 에임의 이야기가 위에 표시됩니다. 탭하면 건물로 돌아갑니다.':'교육지구 건물. 탭하여 빛 펼치기, 드래그 회전, 핀치 확대'); canvas.setAttribute('aria-keyshortcuts','Enter Space'); }
  if (previous !== active) { previous = active; window.webkit?.messageHandlers?.building?.postMessage({kind:'appearance',dark:active}); }
  window.dispatchEvent(new Event('education-viewer-layout'));
}
new MutationObserver(syncAppearance).observe(root,{attributes:true,attributeFilter:['class']});
new MutationObserver(syncAppearance).observe(document.querySelector('#building-stage'),{attributes:true,attributeFilter:['data-renderer']});
syncAppearance();

// Blend the original framing into the lower half using the same morph progress.
let portraitRect;
window.educationViewerRect = (progress=0) => {
  const stage=document.querySelector('#building-stage').getBoundingClientRect();
  if(!root.classList.contains('is-scattered')||!portraitRect){
    portraitRect=innerWidth>innerHeight?{left:.44,right:.98,top:.19,bottom:.70}:{left:.02,right:.98,
      top:Math.min(.40,Math.max(.24,(intro.getBoundingClientRect().bottom-stage.top+20)/stage.height)),
      bottom:Math.max(.58,Math.min(.80,(hint.getBoundingClientRect().top-stage.top-20)/stage.height))};
  }
  const lower={left:.06,right:.94,top:.53,bottom:.95},rect={};
  for(const key of Object.keys(lower))rect[key]=portraitRect[key]+(lower[key]-portraitRect[key])*progress;
  return rect;
};
