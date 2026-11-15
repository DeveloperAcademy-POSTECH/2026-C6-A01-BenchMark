import * as THREE from '@education/three';
import {scatterData} from './render-policy.mjs';

// The original instance matrices never change. Shared uniforms animate both
// shells and cores; picking uses a compact, precomputed endpoint at rest.
export function createSpaceScatter({root,model,positions,pearls,occluders}) {
  const {sizes,offsets,ids,maxDisplacement}=scatterData(model,positions),count=ids.length;
  const progress={value:0},travel={value:0},finish={value:0};
  const morphs=[],entries=[];
  for(const mesh of pearls){
    const core=mesh.name.startsWith('Pearl core / '),name=core?mesh.name.slice(13):mesh.name;
    const group=model.groups.find(g=>g.name===name);
    if(!group)throw Error('Unknown original pearl group: '+name);
    mesh.instanceMatrix.setUsage(THREE.StaticDrawUsage);
    const geometry=mesh.geometry.clone();mesh.geometry=geometry;
    geometry.setAttribute('nativeOffset',new THREE.InstancedBufferAttribute(offsets.slice(group.start*3,(group.start+group.count)*3),3));
    geometry.setAttribute('nativeSize',new THREE.InstancedBufferAttribute(sizes.slice(group.start,group.start+group.count),1));
    const material=mesh.material,baseCompile=material.onBeforeCompile,baseKey=material.customProgramCacheKey.bind(material),key=baseKey();
    material.onBeforeCompile=shader=>{
      baseCompile(shader);
      Object.assign(shader.uniforms,{nativeProgress:progress,nativeTravel:travel,scatterMorph:finish});
      shader.vertexShader='attribute vec3 nativeOffset;attribute float nativeSize;uniform float nativeProgress;uniform float nativeTravel;\n'+shader.vertexShader;
      shader.vertexShader=shader.vertexShader.replace('#include <begin_vertex>',`#include <begin_vertex>
        float nativeScale=nativeSize>0.?mix(1.,nativeSize,nativeProgress):1.-smoothstep(.10,.82,nativeProgress);
        ${core?'nativeScale*=1.-smoothstep(.12,.72,nativeProgress);':''}
        transformed=transformed*nativeScale+nativeOffset*nativeTravel;
      `);
      if(!core){
        shader.uniforms.spaceTint={value:new THREE.Color(group.color==='blue'?0x9edbff:group.color==='green'?0xdae8bd:0xe6efff)};
        shader.fragmentShader='uniform float scatterMorph;uniform vec3 spaceTint;\n'+shader.fragmentShader;
        shader.fragmentShader=shader.fragmentShader.replace('#include <opaque_fragment>',`
          float spaceFacing=clamp(dot(normal,normalize(vViewPosition)),0.,1.);
          float spaceRim=pow(1.-spaceFacing,1.6);
          float pearlKey=dot(normal,normalize(vec3(-.55,.65,.75)));
          float pearlFill=smoothstep(-.45,.8,pearlKey);
          vec3 pearlMilk=mix(vec3(1.,.90,.79),spaceTint,.28);
          vec3 pearlBody=mix(vec3(.18,.24,.36),pearlMilk,pearlFill)*.42;
          float pearlHighlight=pow(max(pearlKey,0.),22.);
          vec3 spaceLight=outgoingLight*.84+pearlBody+vec3(1.,.96,.9)*pearlHighlight*.85
            +mix(vec3(.85,.64,.79),spaceTint,spaceFacing)*spaceRim*.22;
          outgoingLight=mix(outgoingLight,spaceLight,scatterMorph);
          diffuseColor.a*=mix(1.,mix(.78,.96,spaceRim),scatterMorph);
          #include <opaque_fragment>`);
      }
    };
    material.customProgramCacheKey=()=>key+'-native-gpu-morph-v1';
    if(!core){
      const properties={};for(const name of ['transmission','ior','roughness','envMapIntensity','iridescence','clearcoat','clearcoatRoughness','opacity','emissiveIntensity'])properties[name]=material[name];
      morphs.push({material,properties,emissive:material.emissive.clone(),glow:new THREE.Color(group.color==='blue'||group.color==='ice'?0x9bcbe8:0xffe8ca)});
      material.transparent=true;material.needsUpdate=true;
    }
    // No matrix upload during animation. Compact hit-test matrices are built once.
    const groupIds=ids.filter(id=>id>=group.start&&id<group.start+group.count),matrices=new Float32Array(groupIds.length*16);
    for(let i=0;i<groupIds.length;i++){
      const id=groupIds[i],j=id*3,m=i*16;
      matrices[m]=matrices[m+5]=matrices[m+10]=sizes[id];matrices[m+15]=1;
      for(let k=0;k<3;k++)matrices[m+12+k]=positions[j+k]+offsets[j+k];
    }
    entries.push({mesh,core,backing:name.toLowerCase().includes('backing'),pick:{matrices,ids:groupIds}});
  }
  const glowCanvas=document.createElement('canvas');glowCanvas.width=glowCanvas.height=64;
  const ctx=glowCanvas.getContext('2d'),gradient=ctx.createRadialGradient(32,32,0,32,32,32);
  gradient.addColorStop(0,'rgba(255,244,224,.26)');gradient.addColorStop(.27,'rgba(228,236,255,.12)');gradient.addColorStop(1,'rgba(188,215,255,0)');ctx.fillStyle=gradient;ctx.fillRect(0,0,64,64);
  const glowPositions=new Float32Array(count*3),glowOffsets=new Float32Array(count*3);
  ids.forEach((id,i)=>{glowPositions.set(positions.subarray(id*3,id*3+3),i*3);glowOffsets.set(offsets.subarray(id*3,id*3+3),i*3);});
  const geometry=new THREE.BufferGeometry();geometry.setAttribute('position',new THREE.BufferAttribute(glowPositions,3));geometry.setAttribute('nativeOffset',new THREE.BufferAttribute(glowOffsets,3));
  const glowMaterial=new THREE.PointsMaterial({size:model.radius*7,map:new THREE.CanvasTexture(glowCanvas),transparent:true,opacity:0,depthWrite:false,blending:THREE.AdditiveBlending,color:0xe8efff});
  glowMaterial.onBeforeCompile=shader=>{
    shader.uniforms.nativeTravel=travel;shader.vertexShader='attribute vec3 nativeOffset;uniform float nativeTravel;\n'+shader.vertexShader;
    shader.vertexShader=shader.vertexShader.replace('#include <begin_vertex>','#include <begin_vertex>\ntransformed+=nativeOffset*nativeTravel;');
  };
  const glow=new THREE.Points(geometry,glowMaterial);glow.name='Soft pearl halos';glow.frustumCulled=false;glow.visible=false;root.add(glow);
  // Keep shader feature flags fixed: opacity/transmission uniforms need no
  // recompilation on first tap. Transmission preserves the translucent finish.
  const facades=[...new Set(occluders.map(m=>m.material))].map(material=>({material,opacity:material.opacity}));
  facades.forEach(({material})=>{material.transparent=true;material.needsUpdate=true;});
  let endpoint=false;
  function update(t,burst=0){
    progress.value=t;travel.value=t+burst;finish.value=THREE.MathUtils.smoothstep(t,.08,.88);
    for(const entry of entries){
      entry.mesh.visible=entry.core?t<.72:!(t===1&&entry.backing);
      if(!entry.core&&endpoint!==(t===1)){if(t===1)entry.mesh.userData.nativePick=entry.pick;else delete entry.mesh.userData.nativePick;}
    }
    endpoint=t===1;
    for(const original of morphs){
      for(const name of Object.keys(finishProperties))original.material[name]=THREE.MathUtils.lerp(original.properties[name],finishProperties[name],finish.value);
      original.material.emissive.copy(original.emissive).lerp(original.glow,finish.value);
    }
    const fade=1-THREE.MathUtils.smoothstep(t,.12,.84);
    occluders.forEach(mesh=>{mesh.visible=fade>0;});
    facades.forEach(({material,opacity})=>{material.opacity=opacity*fade;});
    glow.visible=t>0;glowMaterial.opacity=finish.value*.3+burst*.45;
  }
  const finishProperties={transmission:.70,ior:1.45,roughness:.19,envMapIntensity:2.15,iridescence:.62,clearcoat:.82,clearcoatRoughness:.13,opacity:.88,emissiveIntensity:.18};
  return {update,count,maxDisplacement,getTransmission:()=>morphs[0].material.transmission};
}
