import {uuidFromBytes} from './education-service.js';

const canvas=(w,h)=>Object.assign(document.createElement('canvas'),{width:w,height:h});
const png=c=>new Promise((resolve,reject)=>c.toBlob(blob=>blob?resolve(blob):reject(Error('카드 이미지를 만들지 못했어요.')),'image/png'));
function lines(ctx,text,width){
 const result=[];for(const paragraph of text.split('\n')){let line='';for(const char of paragraph){if(line&&ctx.measureText(line+char).width>width){result.push(line);line='';}line+=char;}result.push(line);}return result;
}
function drawText(ctx,text,{x,y,width,height,size=42,color='#344329',weight=500}){
 let rows,lineHeight;
 do{ctx.font=`${weight} ${size}px -apple-system,BlinkMacSystemFont,'Pretendard',sans-serif`;rows=lines(ctx,text,width);lineHeight=size*1.65;if(rows.length*lineHeight<=height)break;size-=1;}while(size>16);
 if(rows.length*lineHeight>height)throw Error('카드에 글을 모두 넣지 못했어요. 내용을 조금 줄여 주세요.');
 ctx.fillStyle=color;ctx.textBaseline='top';rows.forEach((row,i)=>ctx.fillText(row,x,y+i*lineHeight));
 return rows.length*lineHeight;
}
export async function renderEducationCard(draft,photo){
 if(!(photo instanceof Blob)||!photo.type.startsWith('image/'))throw Error('카드에 넣을 사진을 선택해 주세요.');
 await document.fonts.ready;
 const photoURL=URL.createObjectURL(photo),image=new Image();image.src=photoURL;
 try{
  await image.decode();
  const front=canvas(1086,1506),back=canvas(1086,1506),a=front.getContext('2d'),b=back.getContext('2d');
  for(const ctx of [a,b]){ctx.fillStyle='#fff9ed';ctx.fillRect(0,0,1086,1506);ctx.strokeStyle='#d4dbc5';ctx.lineWidth=3;ctx.strokeRect(30,30,1026,1446);}
  drawText(a,'오이기부 · 교육지구 2.0',{x:80,y:76,width:926,height:90,size:32,weight:600,color:'#77865b'});
  a.fillStyle='#e8ecdf';a.fillRect(80,180,926,920);
  const scale=Math.min(926/image.naturalWidth,920/image.naturalHeight),w=image.naturalWidth*scale,h=image.naturalHeight*scale;
  a.drawImage(image,80+(926-w)/2,180+(920-h)/2,w,h);
  drawText(a,draft.title,{x:82,y:1155,width:922,height:170,size:54,weight:700});
  drawText(a,draft.display_name,{x:82,y:1380,width:922,height:60,size:30,color:'#788364'});
  drawText(b,draft.theme+' · '+draft.emotion,{x:82,y:80,width:922,height:65,size:28,color:'#788364'});
  const titleHeight=drawText(b,draft.title,{x:82,y:172,width:922,height:220,size:48,weight:700});
  drawText(b,draft.body,{x:82,y:208+titleHeight,width:922,height:1100-titleHeight,size:38});
  drawText(b,draft.display_name+' · 오이기부',{x:82,y:1385,width:922,height:60,size:28,color:'#788364'});
  const previews=[front,back].map(original=>{const c=canvas(724,1004);c.getContext('2d').drawImage(original,0,0,724,1004);return c;});
  const parts=[];for(const c of [front,back,...previews])parts.push(await png(c));
  const buffers=await Promise.all(parts.map(part=>part.arrayBuffer())),domain=new TextEncoder().encode('oi-education-duplex-v1\n');
  const joined=new Uint8Array(domain.length+buffers.reduce((n,v)=>n+v.byteLength,0));joined.set(domain);let offset=domain.length;
  for(const buffer of buffers){joined.set(new Uint8Array(buffer),offset);offset+=buffer.byteLength;}
  const snapshot=uuidFromBytes(new Uint8Array(await crypto.subtle.digest('SHA-256',joined)));
  return {parts,snapshot};
 }finally{URL.revokeObjectURL(photoURL);}
}
