import * as THREE from '@education/three';
import {findAimedPearl} from './aim-selection.mjs';

export function createAimStories({base,canvas,stage,camera,scatterData,radius,storyForPearl}){
  const panel=document.querySelector('#viewerAimStory'),aim=document.querySelector('#viewerAim');
  const projection=new THREE.Matrix4();let active=false,selected=-1,last=0;
  const set=(selector,value)=>{panel.querySelector(selector).textContent=value;};
  function clear(){selected=-1;delete stage.dataset.aimPearl;aim.classList.remove('is-locked');}
  return {
    hide(){base.hide();},
    setScattered(value){
      active=value;clear();base.setScattered(value);
      if(value){set('.aim-story-category','빛에 담긴 이야기');set('.aim-story-message','아래 구슬을 드래그해 가운데 에임에 맞춰보세요.');set('.aim-story-author','');set('.aim-story-source','예시 및 이 기기에 남긴 이야기');}
    },
    update(progress){
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
      set('.aim-story-category',story.category+'의 빛');set('.aim-story-message',story.message);
      set('.aim-story-author',story.author);set('.aim-story-source',story.isExample?'예시 이야기':'이 기기에 남긴 내 이야기');
    }
  };
}
