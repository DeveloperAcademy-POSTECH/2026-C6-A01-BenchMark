// Small pearls cover only a few pixels at the normal phone framing.
export const renderPolicy = Object.freeze({pixelRatio:1.25,transmissionScale:.5,shell:[10,6],core:[6,4]});

// Cache directional support points once; fitting must not allocate/project every
// building pearl 26 times on each pointermove. All returned points are originals.
export function framingPoints(positions) {
  const ids=new Set();
  for(let a=0;a<32;a++)for(let b=0;b<=8;b++){
    const pitch=-Math.PI/2+b*Math.PI/8,y=Math.sin(pitch),r=Math.cos(pitch),x=Math.sin(a*Math.PI/16)*r,z=Math.cos(a*Math.PI/16)*r;
    let best=-Infinity,id=0;
    for(let j=0;j<positions.length;j+=3){const score=x*positions[j]+y*positions[j+1]+z*positions[j+2];if(score>best){best=score;id=j;}}
    ids.add(id);
  }
  return [...ids].map(j=>[positions[j],positions[j+1],positions[j+2]]);
}
export function frameQueue(draw,request=requestAnimationFrame,cancel=cancelAnimationFrame) {
  let frame=0;
  return {schedule(){if(!frame)frame=request(()=>{frame=0;draw();});},cancel(){if(frame)cancel(frame);frame=0;}};
}

const smooth=(a,b,t)=>{const x=Math.max(0,Math.min(1,(t-a)/(b-a)));return x*x*(3-2*x);};
export function scatterScale(size,t,core=false){return (size?1+(size-1)*t:1-smooth(.10,.82,t))*(core?1-smooth(.12,.72,t):1);}
export function scatterData(model,positions,count=10000) {
  const groups=model.groups.filter(g=>!g.name.toLowerCase().includes('backing'));
  const available=groups.reduce((s,g)=>s+g.count,0);
  if(available<count)throw Error('Not enough surface pearls for the 10,000-pearl scene.');
  const sizes=new Float32Array(model.sphereCount),offsets=new Float32Array(positions.length),ids=[];
  let groupIndex=0,groupOffset=0,maxDisplacement=0;
  for(let index=0;index<count;index++){
    const sourceIndex=Math.floor(index*available/count);
    while(sourceIndex>=groupOffset+groups[groupIndex].count)groupOffset+=groups[groupIndex++].count;
    const id=groups[groupIndex].start+sourceIndex-groupOffset;
    sizes[id]=1.5+.55*((id*.61803398875)%1);ids.push(id);
  }
  for(let id=0;id<model.sphereCount;id++){
    const j=id*3,angle=id*2.399963229728653,variation=(id*.61803398875)%1,distance=1.10+variation*.85;
    const x=(positions[j]+.17)/7.3,y=(positions[j+1]-2.25)/2.65,z=(positions[j+2]-.34)/4.2,n=Math.hypot(x,y,z)||1;
    offsets[j]=x/n*distance+Math.sin(angle)*.24;
    offsets[j+1]=y/n*distance*.75+.25+Math.sin(angle*.73)*.20;
    offsets[j+2]=z/n*distance+Math.cos(angle)*.24;
    maxDisplacement=Math.max(maxDisplacement,Math.hypot(offsets[j],offsets[j+1],offsets[j+2]));
  }
  return {sizes,offsets,ids,maxDisplacement};
}
