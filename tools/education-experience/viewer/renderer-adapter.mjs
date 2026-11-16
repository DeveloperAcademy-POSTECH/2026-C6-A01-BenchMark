import {fileURLToPath} from 'node:url';

// Keep app-specific controls in this repository, outside the standalone web source.
export function adaptNativeRenderer(input,{web=false}={}) {
  function replace(needle,value) {
    if (!input.includes(needle)) throw Error('Reviewed renderer changed; inspect native adapter: '+needle.slice(0,70));
    input = input.replace(needle,() => value);
  }
  replace("import {createScatterStories}","import {createScatterStories,nearestPearl}");
  replace("import {createSpaceScatter} from './space-scatter.js?v=burst-5';",`import {createSpaceScatter} from ${JSON.stringify(fileURLToPath(new URL('./native-scatter.mjs',import.meta.url)))};`);
  replace('renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));','renderer.setPixelRatio(Math.min(devicePixelRatio,renderPolicy.pixelRatio));renderer.transmissionResolutionScale=renderPolicy.transmissionScale;');
  replace('new THREE.SphereGeometry(model.radius,16,8)','new THREE.SphereGeometry(model.radius,...renderPolicy.shell)');
  replace('new THREE.SphereGeometry(model.radius*(isNacre?nacreCoreScale:.58),16,8)','new THREE.SphereGeometry(model.radius*(isNacre?nacreCoreScale:.58),...renderPolicy.core)');
  replace('const corners=[];for(let i=0;i<positions.length;i+=9)corners.push(new THREE.Vector3(positions[i],positions[i+1],positions[i+2]));','const corners=framingPoints(positions).map(p=>new THREE.Vector3(...p)),projection=new THREE.Vector3();');
  const projectBounds=`let minX=Infinity,maxX=-Infinity,minY=Infinity,maxY=-Infinity;for(const v of corners){projection.copy(v).project(camera);minX=Math.min(minX,projection.x);maxX=Math.max(maxX,projection.x);minY=Math.min(minY,projection.y);maxY=Math.max(maxY,projection.y);}`;
  replace('const p=corners.map(v=>v.clone().project(camera)),sx=Math.max(...p.map(v=>v.x))-Math.min(...p.map(v=>v.x)),sy=Math.max(...p.map(v=>v.y))-Math.min(...p.map(v=>v.y));',projectBounds+'const sx=maxX-minX,sy=maxY-minY;');
  replace('const p=corners.map(v=>v.clone().project(camera));',projectBounds);
  replace('const cx=(Math.max(...p.map(v=>v.x))+Math.min(...p.map(v=>v.x)))/2,cy=(Math.max(...p.map(v=>v.y))+Math.min(...p.map(v=>v.y)))/2;','const cx=(maxX+minX)/2,cy=(maxY+minY)/2;');
  replace('spaceScatter.update(scatter,burst);setSpaceMix(scatter);render();','spaceScatter.update(scatter,burst);setSpaceMix(0);render();');
  replace('let storyUI;','let storyUI;const queuedFit=frameQueue(()=>{if(!disposed&&!window.__nativePaused&&!document.hidden)fit();});');
  replace('function render(){if(disposed||document.hidden||!visible)return;',"function render(){if(disposed||document.hidden||!visible)return;const started=performance.now();");
  replace('stage.dataset.pearlTransmission=spaceScatter.getTransmission().toFixed(3);}',"stage.dataset.pearlTransmission=spaceScatter.getTransmission().toFixed(3);stage.dataset.renderMs=(performance.now()-started).toFixed(2);stage.dataset.pixelRatio=String(renderer.getPixelRatio());stage.dataset.transmissionScale=String(renderer.transmissionResolutionScale);stage.dataset.fitPoints=String(corners.length);stage.dataset.scatterCompute='gpu-uniforms';}");
  replace('canvas:[canvas.width,canvas.height],yaw,pitch,zoom,scatter,renderer:stage.dataset.renderer',"canvas:[canvas.width,canvas.height],yaw,pitch,zoom,scatter,renderer:stage.dataset.renderer,pixelRatio:renderer.getPixelRatio(),transmissionScale:renderer.transmissionResolutionScale,fitPoints:corners.length,gpuScatter:true,shaderErrors:renderer.info.programs.filter(p=>p.diagnostics?.runnable===false).length,instanceVersions:pearls.map(m=>m.instanceMatrix.version)");
  replace('"building-origin-space-v4"','"garden-unfold-gpu-v1"');
  if(!web){
    replace('const corners=framingPoints(positions).map(p=>new THREE.Vector3(...p)),projection=new THREE.Vector3();','const corners=spaceScatter.framePoints,projection=new THREE.Vector3();');
    replace('const syncSceneUI=createSceneUI({stage,camera,positions,radius:model.radius,renderer});','const syncSceneUI=()=>{};');
    replace('rect=mobile?{left:.03,right:.99,top:.30,bottom:.83}:{left:.118,right:.978,top:.22,bottom:.82}',
      'rect=window.educationViewerRect(scatter)');
    replace('function fit(){storyUI?.hide();','function fit(){');
    replace('let storyUI;const queuedFit=', 'let storyUI,aimUI,arrivalPose,returnPose,fitWidth=0,fitHeight=0;const queuedFit=');
    replace('renderer.setSize(w,h,false);camera.aspect=w/h;','if(w!==fitWidth||h!==fitHeight){renderer.setSize(w,h,false);fitWidth=w;fitHeight=h;}camera.aspect=w/h;');
    replace('spaceScatter.update(scatter,burst);setSpaceMix(0);render();',`spaceScatter.update(scatter,burst);setSpaceMix(0);
      if(!scatterTarget&&arrivalPose&&returnPose){const t=transition.from?1-scatter/transition.from:1;
        const angle=THREE.MathUtils.euclideanModulo(arrivalPose.yaw-returnPose.yaw+Math.PI,Math.PI*2)-Math.PI;
        yaw=t===1?arrivalPose.yaw:returnPose.yaw+angle*t;pitch=THREE.MathUtils.lerp(returnPose.pitch,arrivalPose.pitch,t);zoom=THREE.MathUtils.lerp(returnPose.zoom,arrivalPose.zoom,t);}
      fit();`);
    replace('scatterTarget=scatterTarget?0:1;storyUI.hide();','if(!scatterTarget)arrivalPose={yaw,pitch,zoom};else returnPose={yaw,pitch,zoom};scatterTarget=scatterTarget?0:1;storyUI.hide();');
    replace("stage.dataset.scatterCompute='gpu-uniforms';}","stage.dataset.scatterCompute='gpu-uniforms';aimUI?.update(scatter);}");
    replace("if(e.key==='ArrowUp')pitch=Math.min(.8,pitch+.06);if(e.key==='ArrowDown')pitch=Math.max(.06,pitch-.06);","if(e.key==='ArrowUp')pitch=orbitPitch(pitch,.12,scatterTarget===1);if(e.key==='ArrowDown')pitch=orbitPitch(pitch,-.12,scatterTarget===1);");
  }
  const start = input.indexOf(' const pointers=new Map();let previous,pinch=0;');
  const end = input.indexOf(" canvas.addEventListener('wheel',",start);
  if (start < 0 || end < 0) throw Error('Inspect renderer pointer bindings before packaging.');
  const gestures = `
 const pointerIntent=new PointerIntent(),pointers=pointerIntent.points;
 const tapRaycaster=new THREE.Raycaster(),tapPointer=new THREE.Vector2();
 function hitBuilding(x,y){
  const r=canvas.getBoundingClientRect();
  if(x<r.left||x>r.right||y<r.top||y>r.bottom)return false;
  tapPointer.set((x-r.left)/r.width*2-1,1-(y-r.top)/r.height*2);
  tapRaycaster.setFromCamera(tapPointer,camera);
  return !!nearestPearl(tapRaycaster.ray,storySpheres,model.radius)||tapRaycaster.intersectObjects(occluders,false).length>0;
 }
 const activateBuilding=()=>{if(scatter===scatterTarget&&!animation&&!document.querySelector('dialog[open]'))document.querySelector('#scatterButton').click();};
 storyUI=createScatterStories({canvas,stage,camera,storySpheres,occluders,radius:model.radius,storyForPearl,canHover:()=>${web?'scatterTarget===1&&scatter===1&&!animation&&!pointers.size':'false'}});
 ${web?'':'storyUI=aimUI=createAimStories({base:storyUI,canvas,stage,camera,scatterData:spaceScatter.selection,radius:model.radius,storyForPearl});'}
 installBuildingGestures({canvas,intent:pointerIntent,onStart:()=>storyUI.hide(),
  onRotate:(dx,dy)=>{yaw-=dx*.005;pitch=${web?'THREE.MathUtils.clamp(pitch+dy*.004,.06,.8)':'orbitPitch(pitch,dy*.006,scatterTarget===1)'};queuedFit.schedule();},
  onZoom:ratio=>{zoom=THREE.MathUtils.clamp(zoom*ratio,.7,2.5);queuedFit.schedule();},
  onTap:e=>{if(scatterTarget===1&&scatter===1&&!animation){activateBuilding();return;}if(!scatterTarget&&scatter===0&&!animation&&hitBuilding(e.clientX,e.clientY))activateBuilding();},
  onMode:mode=>{stage.dataset.gestureIntent=mode;${web?'':"if(mode==='idle'&&scatter===1)queuedFit.schedule();"}}
 });
 canvas.setAttribute('role','button');canvas.setAttribute('aria-label','교육지구 2.0 건물. 탭하면 빛이 펼쳐집니다. 드래그로 회전하고 핀치로 확대할 수 있습니다.');
 canvas.addEventListener('click',e=>{if(e.detail===0)activateBuilding();});
 canvas.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();activateBuilding();}});
 canvas.addEventListener('keydown',e=>{if(e.key==='Escape'&&scatterTarget){e.preventDefault();${web?'':"e.stopImmediatePropagation();"}activateBuilding();}});
 document.addEventListener('visibilitychange',()=>{if(document.hidden)queuedFit.cancel();});
 window.addEventListener('education-viewer-layout',fit);
 window.educationBuildingHitTest=(x,y)=>hitBuilding(x,y);
`;
  input = input.slice(0,start)+gestures+input.slice(end);
  return `${web?'':`import {createAimStories} from ${JSON.stringify(fileURLToPath(new URL('./aim-stories.mjs',import.meta.url)))};\nimport {orbitPitch} from ${JSON.stringify(fileURLToPath(new URL('./aim-selection.mjs',import.meta.url)))};\n`}import {renderPolicy,framingPoints,frameQueue} from ${JSON.stringify(fileURLToPath(new URL('./render-policy.mjs',import.meta.url)))};\nimport {PointerIntent,installBuildingGestures} from ${JSON.stringify(fileURLToPath(new URL('./pointer-intent.mjs',import.meta.url)))};\n`+input;
}

export function adaptNativeStories(input,{web=false}={}){
  const replace=(needle,value)=>{if(!input.includes(needle))throw Error('Inspect native story picking adapter: '+needle);input=input.replace(needle,()=>value);};
  replace('const a=mesh.instanceMatrix.array;', 'const pick=mesh.userData.nativePick,a=pick?.matrices??mesh.instanceMatrix.array,limit=pick?.ids.length??mesh.count,sourceIds=pick?.ids??ids;');
  replace('for(let i=0;i<mesh.count;i++){','for(let i=0;i<limit;i++){');
  replace('id:ids?ids[i]:start+i','id:sourceIds?sourceIds[i]:start+i');
  return input;
}
