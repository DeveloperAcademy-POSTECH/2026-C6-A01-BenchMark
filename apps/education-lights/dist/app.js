import {buildGeometry, projectPoint, fitCameraDistance, CAPACITY, MINE_ID, CAMERA_VIEWS, MOBILE_POINT_COUNT, LIGHT_POINT_COUNT} from './geometry.js';

const $=id=>document.getElementById(id);
const format=new Intl.NumberFormat('ko-KR');
const STORAGE='postech-light-prototype-v1';
const UNIT=10000;
const reduceMotion=matchMedia('(prefers-reduced-motion: reduce)');
const mobile=matchMedia('(pointer: coarse), (max-width: 700px)').matches;
const geometry=buildGeometry();
const state={ratio:32,scatter:0,scatterTarget:0,yaw:0,pitch:.26,distance:15,view:'front',autoRotate:false,lightMode:false,mine:null,draftPhoto:null,hover:-1,frameTime:0,fps:0,renderCount:CAPACITY,storageAvailable:true};
try{const saved=JSON.parse(localStorage.getItem(STORAGE)||'null');if(saved&&typeof saved.author==='string'&&typeof saved.message==='string')state.mine={author:saved.author.slice(0,20),message:saved.message.slice(0,160),category:['축하','감사','응원'].includes(saved.category)?saved.category:'응원',photo:typeof saved.photo==='string'&&/^data:image\/jpeg;base64,/.test(saved.photo)&&saved.photo.length<350000?saved.photo:null,verified:saved.verified===true};}catch{state.storageAvailable=false;}
function saveMine(){try{localStorage.setItem(STORAGE,JSON.stringify(state.mine));state.storageAvailable=true;return true;}catch{state.storageAvailable=false;toast('이 브라우저에서는 저장할 수 없어, 현재 화면에서만 유지됩니다.');return false;}}
const baseCount=()=>Math.min(CAPACITY-(state.mine?1:0),Math.round(state.ratio/100*CAPACITY));
const verifiedCount=()=>baseCount()+(state.mine?.verified?1:0);
function refreshProgress(){const n=verifiedCount(),pct=n/CAPACITY*100;$('percentage').textContent=pct.toFixed(1);$('verifiedCount').textContent=format.format(n);$('raisedAmount').replaceChildren(document.createTextNode(format.format(n*UNIT)),Object.assign(document.createElement('span'),{textContent:' 원'}));$('progressFill').style.width=`${pct}%`;$('rangeOutput').textContent=`${state.ratio}%`;$('progressRange').value=state.ratio;}
let toastTimer;
function toast(text){$('toast').textContent=text;$('toast').classList.add('visible');clearTimeout(toastTimer);toastTimer=setTimeout(()=>$('toast').classList.remove('visible'),3500);}

// One point-sprite draw plus a shared, invisible depth shell. The shell removes
// the far facade's visual noise without drawing a solid building. Both passes
// share exactly the same camera and wave, so points stay on their own surface.
const projection=`
uniform vec2 uPointer;
uniform float uPointerOn,uTime,uYaw,uPitch,uDistance,uAspect,uMotion;
vec3 viewSpace(vec3 p){
  float cy=cos(uYaw),sy=sin(uYaw),cp=cos(uPitch),sp=sin(uPitch);
  vec3 r=vec3(p.x*cy+p.z*sy,p.y,-p.x*sy+p.z*cy);
  return vec3(r.x,r.y*cp-r.z*sp,r.y*sp+r.z*cp);
}
vec4 project(vec3 p){
  vec3 v=viewSpace(p);
  float cameraZ=uDistance-v.z;
  vec2 ndc=vec2(v.x*1.83/uAspect,v.y*1.83)/cameraZ;
  float d=length((ndc-uPointer)*vec2(uAspect,1.));
  float wave=sin(d*28.-uTime*5.)*exp(-d*d*22.)*uPointerOn*uMotion*.055;
  v.y+=wave;v.z+=wave*.5;cameraZ=uDistance-v.z;
  return vec4(v.x*1.83/uAspect,v.y*1.83,(cameraZ-.2)/64.*cameraZ,cameraZ);
}`;
const vertex=`
precision highp float;
attribute vec3 aPosition;
attribute vec3 aCloud;
attribute vec3 aNormal;
attribute float aID;
attribute float aBrightness;
uniform float uScatter,uDPR,uHeight,uPointScale,uBlueCount,uMineOn,uMineVerified,uHover;
varying float vBlue,vAlpha,vSelected;
${projection}
void main(){
  vec3 p=mix(aPosition+aNormal*.012,aCloud,uScatter);
  float phase=aID*.3187;
  p+=vec3(sin(uTime*.25+phase),cos(uTime*.21+phase),sin(uTime*.18+phase*.8))*.012*uMotion*uScatter;
  gl_Position=project(p);
  float cameraZ=gl_Position.w;
  bool mine=abs(aID-${MINE_ID}.0)<.1 && uMineOn>.5;
  vBlue=mine?uMineVerified:step(aID+.5,uBlueCount);
  vSelected=max(mine?1.:0.,abs(aID-uHover)<.1?1.:0.);
  float densityScale=clamp(uHeight/700.,.44,1.);
  // Fine, closely packed spheres. LOD compensation is capped so reduced-detail
  // phones never turn the surface back into oversized beads.
  float size=mix(4.9*uPointScale,2.8,uScatter);
  gl_PointSize=clamp((size+vSelected*1.2)*densityScale*uDPR*12.5/cameraZ,1.0,11.*uDPR);
  float facing=.52+.38*max(0.,viewSpace(aNormal).z);
  vAlpha=(.56+aBrightness*.44)*mix(facing,1.,uScatter);
}`;
const fragment=`
precision mediump float;
varying float vBlue,vAlpha,vSelected;
void main(){
  vec2 uv=gl_PointCoord*2.-1.;float d=dot(uv,uv);if(d>1.)discard;
  float z=sqrt(1.-d);
  float diffuse=max(0.,dot(vec3(uv.x,-uv.y,z),normalize(vec3(-.45,.65,1.))));
  float core=1.-smoothstep(.4,1.,d);
  float light=.73+diffuse*.27;
  vec3 white=vec3(.94,.97,1.),blue=vec3(.12,.53,1.);
  vec3 color=mix(white,blue,vBlue)*light;
  color+=vec3(.35,.44,.58)*pow(diffuse,12.)*.08;
  color=mix(color,vec3(.72,.90,1.),vSelected*.28);
  float alpha=(.32+core*.65)*vAlpha*(1.-smoothstep(.7,1.,d));
  gl_FragColor=vec4(color,alpha);
}`;
const depthVertex=`precision highp float;attribute vec3 aPosition;${projection}void main(){gl_Position=project(aPosition);}`;
const depthFragment=`precision mediump float;void main(){gl_FragColor=vec4(0.);}`;
const canvas=$('building'), gl=canvas.getContext('webgl',{alpha:false,antialias:false,depth:true,powerPreference:'low-power',preserveDrawingBuffer:false});
let program,depthProgram,uniforms={},depthUniforms={},attributes=[],depthAttribute,buffer,depthBuffer,raf=0,width=1,height=1,dpr=1,paused=false,inViewport=true,contextLost=false,lastDraw=0,lastPick=0,pointerX=10,pointerY=10,pointerStrength=0,targetPointerStrength=0,fittedDistance=15;
function shader(type,source){const s=gl.createShader(type);gl.shaderSource(s,source);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw new Error(gl.getShaderInfoLog(s));return s;}
function link(vertexSource,fragmentSource){const p=gl.createProgram(),vs=shader(gl.VERTEX_SHADER,vertexSource),fs=shader(gl.FRAGMENT_SHADER,fragmentSource);gl.attachShader(p,vs);gl.attachShader(p,fs);gl.linkProgram(p);if(!gl.getProgramParameter(p,gl.LINK_STATUS))throw new Error(gl.getProgramInfoLog(p));gl.deleteShader(vs);gl.deleteShader(fs);return p;}
const cameraUniformNames=['uPointer','uPointerOn','uTime','uYaw','uPitch','uDistance','uAspect','uMotion'];
function initGL(){
  program=link(vertex,fragment);depthProgram=link(depthVertex,depthFragment);
  buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,geometry.vertices,gl.STATIC_DRAW);
  attributes=[['aPosition',3,0],['aCloud',3,12],['aID',1,24],['aBrightness',1,28],['aNormal',3,32]].map(([name,size,offset])=>({index:gl.getAttribLocation(program,name),size,offset}));
  for(const name of [...cameraUniformNames,'uScatter','uDPR','uHeight','uPointScale','uBlueCount','uMineOn','uMineVerified','uHover'])uniforms[name]=gl.getUniformLocation(program,name);
  depthBuffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,depthBuffer);gl.bufferData(gl.ARRAY_BUFFER,geometry.occluders,gl.STATIC_DRAW);
  depthAttribute=gl.getAttribLocation(depthProgram,'aPosition');for(const name of cameraUniformNames)depthUniforms[name]=gl.getUniformLocation(depthProgram,name);
  // Alpha compositing keeps overlapping roof samples from burning to white;
  // their front/back depth and blue participation colours remain legible.
  gl.enable(gl.BLEND);gl.blendFunc(gl.SRC_ALPHA,gl.ONE_MINUS_SRC_ALPHA);gl.depthFunc(gl.LEQUAL);gl.clearColor(5/255,7/255,11/255,1);resize();
}
function fitCamera(reset=false){
  const distance=fitCameraDistance(geometry.positions,state.yaw,state.pitch,width/height);
  state.distance=distance*(reset?1:state.distance/fittedDistance);fittedDistance=distance;
}
function resize(){const rect=canvas.getBoundingClientRect();width=Math.max(1,rect.width);height=Math.max(1,rect.height);dpr=Math.min(devicePixelRatio||1,state.lightMode?1:mobile?1.35:1.7);canvas.width=Math.round(width*dpr);canvas.height=Math.round(height*dpr);gl?.viewport(0,0,canvas.width,canvas.height);fitCamera();}
function applyCamera(u,now){gl.uniform1f(u.uTime,now*.001);gl.uniform1f(u.uYaw,state.yaw);gl.uniform1f(u.uPitch,state.pitch);gl.uniform1f(u.uDistance,state.distance);gl.uniform1f(u.uAspect,width/height);gl.uniform1f(u.uPointerOn,pointerStrength);gl.uniform1f(u.uMotion,reduceMotion.matches?0:1);gl.uniform2f(u.uPointer,pointerX,pointerY);}
function draw(now){
  if(paused||!gl)return;
  raf=requestAnimationFrame(draw);
  const interval=mobile||state.lightMode?1000/30:1000/60;
  if(now-lastDraw<interval-1)return;
  const elapsed=Math.min(64,now-lastDraw||16.67),dt=elapsed/1000;lastDraw=now;
  const start=performance.now();
  state.scatter+= (state.scatterTarget-state.scatter)*(reduceMotion.matches?1:1-Math.exp(-dt*4));
  if(Math.abs(state.scatterTarget-state.scatter)<.0001)state.scatter=state.scatterTarget;
  pointerStrength+=(targetPointerStrength-pointerStrength)*.15;
  if(state.autoRotate&&!reduceMotion.matches&&pointers.size===0)state.yaw+=dt*.075;
  gl.depthMask(true);gl.clear(gl.COLOR_BUFFER_BIT|gl.DEPTH_BUFFER_BIT);
  if(state.scatter<.04){
    gl.enable(gl.DEPTH_TEST);gl.disable(gl.BLEND);gl.colorMask(false,false,false,false);gl.useProgram(depthProgram);applyCamera(depthUniforms,now);
    for(const a of attributes)gl.disableVertexAttribArray(a.index);
    gl.bindBuffer(gl.ARRAY_BUFFER,depthBuffer);gl.enableVertexAttribArray(depthAttribute);gl.vertexAttribPointer(depthAttribute,3,gl.FLOAT,false,12,0);
    gl.enable(gl.POLYGON_OFFSET_FILL);gl.polygonOffset(1,1);gl.drawArrays(gl.TRIANGLES,0,geometry.occluders.length/3);gl.disable(gl.POLYGON_OFFSET_FILL);
    gl.colorMask(true,true,true,true);gl.enable(gl.BLEND);
  }else gl.disable(gl.DEPTH_TEST);
  gl.depthMask(false);gl.useProgram(program);applyCamera(uniforms,now);gl.bindBuffer(gl.ARRAY_BUFFER,buffer);
  for(const a of attributes){gl.enableVertexAttribArray(a.index);gl.vertexAttribPointer(a.index,a.size,gl.FLOAT,false,44,a.offset);}
  const one=(key,value)=>gl.uniform1f(uniforms[key],value);
  state.renderCount=state.lightMode?LIGHT_POINT_COUNT:mobile?MOBILE_POINT_COUNT:CAPACITY;
  one('uScatter',state.scatter);one('uDPR',dpr);one('uHeight',height);one('uPointScale',Math.min(1.22,Math.pow(CAPACITY/state.renderCount,.18)));one('uBlueCount',baseCount());one('uMineOn',state.mine?1:0);one('uMineVerified',state.mine?.verified?1:0);one('uHover',state.hover<0?-1:geometry.ids[state.hover]);
  gl.drawArrays(gl.POINTS,0,state.renderCount);
  if(state.mine&&geometry.mineIndex>=state.renderCount)gl.drawArrays(gl.POINTS,geometry.mineIndex,1);
  state.frameTime=performance.now()-start;state.fps=1000/elapsed;
}
function start(){if(!gl||contextLost||document.hidden||!inViewport){paused=true;cancelAnimationFrame(raf);return;}$('fallback').hidden=true;paused=false;cancelAnimationFrame(raf);lastDraw=performance.now();raf=requestAnimationFrame(draw);}
if(!gl){$('fallback').hidden=false;}else{try{initGL();}catch(error){console.error('Renderer initialization failed',error);$('fallback').hidden=false;paused=true;}}
canvas.addEventListener('webglcontextlost',event=>{event.preventDefault();contextLost=true;paused=true;cancelAnimationFrame(raf);$('fallback').hidden=false;$('fallback').textContent='화면을 잠시 쉬고 있어요. 잠시 후 자동으로 복원합니다.';});
canvas.addEventListener('webglcontextrestored',()=>{try{contextLost=false;initGL();start();}catch{$('fallback').hidden=false;}});
new ResizeObserver(()=>{if(gl)resize();}).observe(canvas);
document.addEventListener('visibilitychange',()=>{if(document.hidden){paused=true;cancelAnimationFrame(raf);}else start();});
new IntersectionObserver(entries=>{inViewport=entries[0].isIntersecting;if(inViewport)start();else{paused=true;cancelAnimationFrame(raf);}},{rootMargin:'60px'}).observe(canvas);

function setScatter(force){state.scatterTarget=force??(state.scatterTarget?0:1);const open=state.scatterTarget===1;$('scatterLabel').textContent=open?'건물로 모으기':'빛 흩어보기';$('scatterSymbol').textContent=open?'⌘':'⠿';$('sceneState').innerHTML=open?'<i></i> 저마다의 이야기를 가진 작은 빛들':'<i></i> 하나의 마음, 하나의 공간';canvas.setAttribute('aria-label',open?'흩어진 빛. Enter 또는 탭으로 건물로 모으기':'교육지구 빛 조형물. Enter 또는 탭으로 흩어보기');$('scene').dataset.scattered=String(open);}
$('scatterButton').addEventListener('click',()=>setScatter());
$('rotateButton').addEventListener('click',()=>{state.autoRotate=!state.autoRotate;if(state.autoRotate)clearViewSelection();$('rotateButton').setAttribute('aria-pressed',state.autoRotate);$('rotateButton').setAttribute('aria-label',state.autoRotate?'자동 회전 멈추기':'자동 회전 시작');if(reduceMotion.matches&&state.autoRotate)toast('동작 줄이기가 설정되어 자동 회전은 쉬고 있어요.');});
function clearViewSelection(){state.view=null;for(const b of document.querySelectorAll('[data-view]'))b.setAttribute('aria-pressed','false');}
function selectView(name){const view=CAMERA_VIEWS[name];if(!view)return;state.view=name;state.yaw=view.yaw;state.pitch=view.pitch;state.autoRotate=false;$('rotateButton').setAttribute('aria-pressed','false');$('rotateButton').setAttribute('aria-label','자동 회전 시작');fitCamera(true);setScatter(0);for(const b of document.querySelectorAll('[data-view]'))b.setAttribute('aria-pressed',String(b.dataset.view===name));}
for(const b of document.querySelectorAll('[data-view]'))b.addEventListener('click',()=>selectView(b.dataset.view));
$('resetView').addEventListener('click',()=>selectView('front'));
$('performanceButton').addEventListener('click',()=>{state.lightMode=!state.lightMode;$('performanceButton').setAttribute('aria-pressed',state.lightMode);$('performanceButton').setAttribute('aria-label',state.lightMode?'가벼운 모드 끄기':'가벼운 모드 켜기');resize();toast(state.lightMode?'가벼운 모드 · 24,000개 대표 점으로 표시합니다.':mobile?'모바일 모드 · 48,000개 대표 점으로 표시합니다.':'기본 모드 · 96,000개 빛을 모두 표시합니다.');});
const pointers=new Map();let tapStart=null,dragged=false,pinchDistance=0;
canvas.addEventListener('pointerdown',event=>{canvas.setPointerCapture(event.pointerId);pointers.set(event.pointerId,{x:event.clientX,y:event.clientY});if(pointers.size===1){tapStart={x:event.clientX,y:event.clientY,time:performance.now()};dragged=false;}else{dragged=true;const [a,b]=[...pointers.values()];pinchDistance=Math.hypot(a.x-b.x,a.y-b.y);}});
canvas.addEventListener('pointermove',event=>{
  const rect=canvas.getBoundingClientRect(),x=event.clientX-rect.left,y=event.clientY-rect.top;
  pointerX=x/width*2-1;pointerY=1-y/height*2;targetPointerStrength=1;
  const previous=pointers.get(event.pointerId);
  if(previous){const dx=event.clientX-previous.x,dy=event.clientY-previous.y;pointers.set(event.pointerId,{x:event.clientX,y:event.clientY});if(pointers.size===2){const[a,b]=[...pointers.values()],dist=Math.hypot(a.x-b.x,a.y-b.y);if(pinchDistance>0)state.distance=Math.max(6,Math.min(35,state.distance*pinchDistance/dist));pinchDistance=dist;dragged=true;}else{if(tapStart&&Math.hypot(event.clientX-tapStart.x,event.clientY-tapStart.y)>5)dragged=true;if(dragged){state.yaw+=dx*.005;state.pitch=Math.max(-.22,Math.min(1.1,state.pitch+dy*.004));clearViewSelection();}}$('pointTooltip').hidden=true;
  }else if(performance.now()-lastPick>85){lastPick=performance.now();pick(x,y);}
});
function finishPointer(event,cancelled=false){const existed=pointers.delete(event.pointerId);if(existed&&!cancelled&&pointers.size===0&&!dragged&&tapStart&&performance.now()-tapStart.time<500)setScatter();if(pointers.size===0){tapStart=null;targetPointerStrength=event.pointerType==='touch'?0:1;}else dragged=true;}
canvas.addEventListener('pointerup',event=>finishPointer(event));canvas.addEventListener('pointercancel',event=>finishPointer(event,true));canvas.addEventListener('lostpointercapture',event=>{if(pointers.has(event.pointerId))finishPointer(event,true);});
canvas.addEventListener('pointerleave',()=>{targetPointerStrength=0;state.hover=-1;$('pointTooltip').hidden=true;});
canvas.addEventListener('wheel',event=>{event.preventDefault();state.distance=Math.max(6,Math.min(35,state.distance+event.deltaY*.008));},{passive:false});
canvas.addEventListener('keydown',event=>{if(['Enter',' ','ArrowLeft','ArrowRight','ArrowUp','ArrowDown','+','=','-','Escape'].includes(event.key)){event.preventDefault();if(event.key.startsWith('Arrow'))clearViewSelection();if(event.key==='Enter'||event.key===' ')setScatter();else if(event.key==='ArrowLeft')state.yaw-=.12;else if(event.key==='ArrowRight')state.yaw+=.12;else if(event.key==='ArrowUp')state.pitch=Math.min(1.1,state.pitch+.08);else if(event.key==='ArrowDown')state.pitch=Math.max(-.22,state.pitch-.08);else if(event.key==='-' )state.distance=Math.min(35,state.distance+.7);else if(event.key==='Escape')setScatter(0);else state.distance=Math.max(6,state.distance-.7);}});
function pick(x,y){let best=-1,bestScore=144;const a=geometry.positions,b=geometry.clouds,s=state.scatter;
  for(let i=0;i<state.renderCount;i++){const j=i*3;const p=projectPoint(a[j]*(1-s)+b[j]*s,a[j+1]*(1-s)+b[j+1]*s,a[j+2]*(1-s)+b[j+2]*s,state.yaw,state.pitch,state.distance,width/height);const px=(p[0]+1)*.5*width,py=(1-p[1])*.5*height;const d=(px-x)**2+(py-y)**2;if(d<bestScore){bestScore=d;best=i;}}
  state.hover=best;if(best<0){$('pointTooltip').hidden=true;return;}const id=geometry.ids[best],isMine=id===MINE_ID&&state.mine,blue=isMine?state.mine.verified:id<baseCount();$('pointLabel').textContent=isMine?'내가 남긴 빛':`${blue?'인증된':'기다리는'} 빛 · ${String(id+1).padStart(4,'0')}`;$('pointTooltip').querySelector('i').className=`orb ${blue?'blue':'white'}`;$('pointTooltip').style.left=`${Math.min(width-165,Math.max(10,x+15))}px`;$('pointTooltip').style.top=`${Math.max(38,y-34)}px`;$('pointTooltip').hidden=false;
}

$('progressRange').addEventListener('input',event=>{state.ratio=Number(event.target.value);refreshProgress();});
$('simulationToggle').addEventListener('click',()=>{const open=$('simulationToggle').getAttribute('aria-expanded')!=='true';$('simulationToggle').setAttribute('aria-expanded',String(open));$('simulationBody').hidden=!open;$('simulationChevron').textContent=open?'−':'＋';});
for(const dialog of document.querySelectorAll('dialog')){dialog.querySelector('[data-close]').addEventListener('click',()=>dialog.close());dialog.addEventListener('click',event=>{if(event.target===dialog){const r=dialog.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)dialog.close();}});}
function openWrite(){
  ++photoGeneration;photoBusy=false;$('storyForm').querySelector('button[type=submit]').disabled=false;
  $('writePanel').hidden=false;$('readPanel').hidden=true;$('dialogOrb').classList.remove('verified');$('storyEyebrow').textContent='YOUR LITTLE LIGHT';$('authorInput').value=state.mine?.author||'';$('messageInput').value=state.mine?.message||'';$('messageCount').textContent=`${$('messageInput').value.length} / 160`;const category=state.mine?.category||'축하';document.querySelector(`input[name=category][value="${category}"]`).checked=true;state.draftPhoto=state.mine?.photo||null;$('formError').textContent='';$('photoInput').value='';refreshPhoto();if(!$('storyDialog').open)$('storyDialog').showModal();
}
function refreshPhoto(){const show=Boolean(state.draftPhoto);$('photoPreview').hidden=!show;$('photoPrompt').hidden=show;$('removePhoto').hidden=!show;if(show)$('photoPreview').src=state.draftPhoto;else $('photoPreview').removeAttribute('src');}
$('messageInput').addEventListener('input',()=>{$('messageCount').textContent=`${$('messageInput').value.length} / 160`;});
let photoGeneration=0,photoBusy=false;
$('photoInput').addEventListener('change',async event=>{
  const file=event.target.files[0],generation=++photoGeneration;if(!file)return;
  if(!file.type.startsWith('image/')){toast('이미지 파일을 선택해주세요.');return;}
  if(file.size>25*1024*1024){toast('25MB 이하의 사진을 선택해주세요.');return;}
  photoBusy=true;$('storyForm').querySelector('button[type=submit]').disabled=true;
  let url;
  try{url=URL.createObjectURL(file);const image=new Image();image.src=url;await image.decode();const scale=Math.min(1,768/Math.max(image.naturalWidth,image.naturalHeight)),c=document.createElement('canvas');c.width=Math.max(1,Math.round(image.naturalWidth*scale));c.height=Math.max(1,Math.round(image.naturalHeight*scale));const context=c.getContext('2d');context.fillStyle='#ffffff';context.fillRect(0,0,c.width,c.height);context.drawImage(image,0,0,c.width,c.height);const photo=c.toDataURL('image/jpeg',.8);if(generation===photoGeneration){if(photo.length>350000){toast('더 작은 사진을 선택해주세요.');}else{state.draftPhoto=photo;refreshPhoto();}}}
  catch{toast('이 사진을 읽지 못했어요. JPG 또는 PNG 사진을 선택해주세요.');}
  finally{if(url)URL.revokeObjectURL(url);if(generation===photoGeneration){photoBusy=false;$('storyForm').querySelector('button[type=submit]').disabled=false;}}
});
$('removePhoto').addEventListener('click',()=>{++photoGeneration;photoBusy=false;$('storyForm').querySelector('button[type=submit]').disabled=false;state.draftPhoto=null;$('photoInput').value='';refreshPhoto();});
$('storyForm').addEventListener('submit',event=>{event.preventDefault();if(photoBusy)return;const author=$('authorInput').value.trim(),message=$('messageInput').value.trim();if(!author||!message){$('formError').textContent='이름과 메시지를 입력해주세요.';return;}state.mine={author,message,category:new FormData(event.target).get('category'),photo:state.draftPhoto,verified:state.mine?.verified||false};saveMine();refreshProgress();openRead(state.mine,true);toast('내 이야기를 담은 하나의 빛이 생겼어요.');});
function openRead(story,mine=false){$('writePanel').hidden=true;$('readPanel').hidden=false;$('storyEyebrow').textContent=mine?'YOUR LITTLE LIGHT':'A LIGHT WITH A STORY';$('dialogOrb').classList.toggle('verified',Boolean(story.verified));$('readCategory').textContent=story.category;$('readTitle').textContent=mine?'내가 남긴 빛':'공간에 남겨진 마음';$('readMessage').textContent=story.message;$('readAuthor').textContent=`${story.author} 님이 남긴 마음${mine?'':' · 시연 메시지'}`;$('readPhoto').hidden=!story.photo;if(story.photo)$('readPhoto').src=story.photo;else $('readPhoto').removeAttribute('src');$('storyStatus').textContent=story.verified?'푸른 빛 · 기부 인증을 가정한 시연 상태입니다. 실제 기부·납입 확인과 연결되어 있지 않습니다.':'흰 빛 · 이야기를 보관했어요. 아래 버튼으로 기부 인증 후 푸르게 바뀌는 모습을 체험해보세요.';$('verifyButton').hidden=!mine||story.verified;$('editButton').hidden=!mine;if(!$('storyDialog').open)$('storyDialog').showModal();if(mine){setScatter(0);state.hover=geometry.mineIndex;}}
$('writeButton').addEventListener('click',()=>state.mine?openRead(state.mine,true):openWrite());$('editButton').addEventListener('click',openWrite);
$('verifyButton').addEventListener('click',()=>{if(!state.mine||state.mine.verified)return;state.mine.verified=true;saveMine();refreshProgress();openRead(state.mine,true);toast('인증 시연 완료 · 나의 흰 빛이 파란 빛으로 바뀌었어요.');});
const examples=[{category:'응원',author:'새로운 꿈을 응원하는 동문',message:'이곳에서 시작될 수많은 질문들이\n세상을 조금 더 좋은 곳으로 만들기를.',verified:true},{category:'감사',author:'배움을 기억하는 졸업생',message:'마음껏 도전할 수 있었던 시간에 감사합니다.\n다음 세대의 가능성에도 작은 빛을 보탭니다.',verified:true},{category:'축하',author:'내일을 기다리는 학생',message:'우리의 새로운 배움터를 축하해요.\n이 공간에서 만날 내일이 벌써 기대됩니다.',verified:true}];
function openInfo(html){$('infoContent').innerHTML=html;$('infoDialog').showModal();}
$('storiesButton').addEventListener('click',()=>{openInfo('<h2>빛 하나에,<br>이야기 하나.</h2><p>아래는 경험을 확인하기 위한 예시 메시지입니다.<br>내가 남긴 이야기는 이 브라우저에서만 보입니다.</p><div class="story-list" id="storyList"></div>');const list=$('storyList');const stories=[...(state.mine?[{story:state.mine,mine:true}]:[]),...(baseCount()>0?examples.map(story=>({story,mine:false})):[])];if(!stories.length){const p=document.createElement('p');p.textContent='아직 인증된 빛이 없어요. 나의 빛을 남기거나 모금률을 움직여보세요.';list.append(p);}stories.forEach(({story,mine})=>{const button=document.createElement('button'),small=document.createElement('small'),p=document.createElement('p'),span=document.createElement('span');small.textContent=mine?'나의 빛':`${story.category}의 빛 · 예시`;p.textContent=story.message;span.textContent=story.author;button.append(small,p,span);button.addEventListener('click',()=>{$('infoDialog').close();openRead(story,mine);});list.append(button);});});
$('aboutButton').addEventListener('click',()=>openInfo('<h2>마음이 모여,<br>공간이 되는 순간.</h2><p>POSTECH 교육지구 2.0의 건물 형상을 작은 반투명 구들로 표현한 인터랙티브 콘셉트입니다. 흰 빛은 기다리는 자리, 푸른 빛은 기부가 인증된 참여자를 나타냅니다.</p><img src="./reference.jpg" alt="긴 곡면 외벽과 층층의 테라스, 상부 사다리꼴 매스가 있는 건물 기준 이미지"><p class="reference-caption">앞서 생성한 건물 기준 이미지. 점 조형물은 이 이미지를 해석한 형상이며 실제 설계 모델이 아닙니다.</p><p>한 사람당 하나의 구에 축하·감사·응원의 메시지와 사진을 담습니다. 모금률과 파란 구의 비율은 동일 금액 기부를 가정한 시연에서만 일치합니다. 실제 서비스에서는 인증된 금액의 합계와 참여 인원을 각각 집계해야 합니다.</p><p>목표액, 참여 인원, 메시지와 인증은 모두 시연용입니다. 기부금 수납·학교의 공식 납입 확인·영수증 발급 기능은 연결하지 않았습니다.</p><p><a href="https://www.postech.ac.kr/kor/innovation/education_district_cp.do" target="_blank" rel="noopener noreferrer">POSTECH 공식 사업 소개 ↗</a></p>'));
$('referenceButton').addEventListener('click',()=>openInfo('<h2>네 방향의 기준 이미지</h2><p>긴 외벽과 옥상 중정, 왼쪽의 높은 상부, 오른쪽의 계단식 테라스를 하나의 입체 형상으로 연결했습니다. 화면의 정면·좌측·우측·뒷면 버튼으로 각 방향을 확인할 수 있습니다.</p><div class="reference-grid">'+[['front','정면'],['left','좌측면'],['right','우측면'],['back','뒷면']].map(([id,label])=>`<figure><img src="./references/${id}.jpg" alt="교육지구 건물 ${label} 기준 이미지" width="960" height="640" loading="lazy"><figcaption>${label}</figcaption></figure>`).join('')+'</div><p class="reference-caption">제공된 생성 이미지를 해석한 3D 조형물입니다. 실제 설계 도면을 복원한 모델은 아닙니다.</p>'));
$('specButton').addEventListener('click',()=>openInfo(`<h2>작은 빛,<br>가벼운 경험.</h2><p>총 96,000개 구로 외벽과 지붕, 테라스를 촘촘하게 표현합니다. 휴대폰은 48,000개, 가벼운 모드는 24,000개 대표 점으로 같은 형태를 표시하며 기부 집계는 그대로 유지합니다.</p><ul><li>구마다 메시를 만들지 않고 구처럼 보이는 WebGL 점 스프라이트 사용</li><li>점 표시 1회 + 가려진 면을 판별하는 깊이 처리 1회</li><li>사진 텍스처·실시간 그림자·후처리 없음</li><li>휴대폰 30fps 상한 · 화면 배율 최대 1.35배</li><li>화면 밖·백그라운드 렌더링 중단 · 동작 줄이기 대응</li><li>사진 긴 변 최대 768px, JPEG 축소 저장</li></ul><p>현재 ${state.renderCount.toLocaleString()}개 표시 · 프레임 제출 CPU ${state.frameTime.toFixed(2)}ms. 이 값은 GPU 시간이나 실제 iPhone 성능 보장을 뜻하지 않습니다. 실기기 발열·배터리 검증은 별도로 필요합니다.</p>`));

// Read-only diagnostics for visual/performance QA, not a service API.
window.prototypeDiagnostics=()=>({revision:geometry.revision,view:state.view,camera:{yaw:state.yaw,pitch:state.pitch,distance:state.distance},capacity:CAPACITY,renderCount:state.renderCount,verified:verifiedCount(),raised:verifiedCount()*UNIT,ratio:state.ratio,scatter:state.scatter,scatterTarget:state.scatterTarget,cpuFrameMs:state.frameTime,fps:state.fps,bufferBytes:geometry.vertices.byteLength+geometry.occluders.byteLength,depthTriangles:geometry.occluders.length/9,canvas:[canvas.width,canvas.height],dpr,mobile,paused,mine:state.mine?{verified:state.mine.verified,hasPhoto:Boolean(state.mine.photo)}:null,webgl:!!gl});
refreshProgress();if(gl&&!paused)start();
