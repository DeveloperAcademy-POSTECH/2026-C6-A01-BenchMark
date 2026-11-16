import * as THREE from '@education/three';
import {findAimedPearl} from './aim-selection.mjs';
import {educationReady} from '@education/library';

export function createAimStories({base,canvas,stage,camera,scatterData,radius,storyForPearl}){
  const panel=document.querySelector('#viewerAimStory'),aim=document.querySelector('#viewerAim');
  const photo=panel.querySelector('#viewerAimPhoto'),content=panel.querySelector('.aim-story-content');
  const projection=new THREE.Matrix4();let active=false,selected=-1,last=0,progressValue=0,previewRelease=null,previewStory=null,currentStory=null;
  const set=(selector,value)=>{panel.querySelector(selector).textContent=value;};
  function mountThumbnail(story){
    let cancelled=false;const image=photo.querySelector('img');photo.classList.remove('is-ready');
    const timer=setTimeout(async()=>{
      try{
        let url=story.photo;
        if(story.origin==='education'){
          const service=await educationReady(),row=await service.story(story.id);
          if(!row||row.status!=='published'||!row.photo_paths?.[0])throw Error('Story photo unavailable');
          url=await service.media(row.photo_paths[0]);
        }
        if(cancelled)return;
        image.crossOrigin='anonymous';image.alt=story.origin==='postech'?story.photoAlt:story.title+' 이야기 사진';image.src=url;await image.decode();
        if(!cancelled)photo.classList.add('is-ready');
      }catch{if(!cancelled)photo.querySelector('.pearl-note-photo-placeholder').textContent='사진을 불러오지 못했어요';}
    },140);
    return ()=>{cancelled=true;clearTimeout(timer);image.removeAttribute('src');photo.classList.remove('is-ready');};
  }
  function clear(){previewRelease?.();previewRelease=null;previewStory=null;currentStory=null;photo.hidden=true;delete photo.dataset.storyId;selected=-1;delete stage.dataset.aimPearl;aim.classList.remove('is-locked');}
  photo.querySelector('button').addEventListener('click',()=>{if(currentStory)window.dispatchEvent(new CustomEvent(currentStory.origin==='postech'?'education-open-reference':'education-open-story',{detail:{id:currentStory.id}}));});
  const controller={
    prepare(){},
    hide(){base.hide();},
    setScattered(value){
      active=value;clear();base.setScattered(value);
      if(value){set('.aim-story-category','빛에 담긴 이야기');set('.aim-story-message','아래 구슬을 드래그해 가운데 에임에 맞춰보세요.');set('.aim-story-author','');set('.aim-story-source','앱과 웹에 공유된 이야기');}
    },
    update(progress){
      progressValue=progress;
      if(!active||progress!==1||document.hidden||window.__nativePaused)return;
      const now=performance.now();if(now-last<70&&stage.dataset.gestureIntent!=='idle')return;last=now;
      const rect=canvas.getBoundingClientRect(),target=aim.getBoundingClientRect();
      projection.multiplyMatrices(camera.projectionMatrix,camera.matrixWorldInverse);
      const hit=findAimedPearl({...scatterData,matrix:projection.elements,projectionY:camera.projectionMatrix.elements[5],width:rect.width,height:rect.height,x:target.left+target.width/2-rect.left,y:target.top+target.height/2-rect.top,radius,previous:selected});
      if(!hit){clear();return;}
      aim.classList.add('is-locked');
      if(selected===hit.id)return;
      selected=hit.id;stage.dataset.aimPearl=String(hit.id);
      const story=storyForPearl(hit.id);
      const previewKey=JSON.stringify([story.id,story.photo,story.remote?.revision,story.remote?.card_snapshot_id]);
      if(previewStory!==previewKey){
        previewRelease?.();previewRelease=null;previewStory=previewKey;currentStory=null;photo.hidden=true;delete photo.dataset.storyId;content.scrollTop=0;
        if(story.origin==='education'||story.origin==='postech'){
          currentStory=story;photo.hidden=false;photo.dataset.storyId=story.id;
          photo.querySelector('.pearl-note-photo-placeholder').textContent='사진을 불러오는 중';
          photo.querySelector('button').setAttribute('aria-label',story.title+' 이야기 자세히 보기');
          previewRelease=mountThumbnail(story);
        }
      }
      set('.aim-story-category',story.category+'의 빛');set('.aim-story-message',story.message);
      set('.aim-story-author',story.author);set('.aim-story-source',story.origin==='education'?'앱과 웹에 공유된 교육지구 이야기':story.origin==='postech'?'POSTECH 발전기금 · 원문 요약':'공유 이야기 서버 연결 상태');
    }
  };
  window.addEventListener('education-stories-updated',()=>{selected=-1;last=0;controller.update(progressValue);});
  return controller;
}
