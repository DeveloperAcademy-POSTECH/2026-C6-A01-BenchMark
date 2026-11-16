// Project cached endpoints without allocating a vector for every pearl.
export function findAimedPearl({positions,ids,sizes,matrix,width,height,x,y,radius,projectionY=Math.abs(matrix[5]),previous=-1}) {
  let best=null,old=null;
  for(let i=0;i<ids.length;i++){
    const id=ids[i],j=i*3,px=positions[j],py=positions[j+1],pz=positions[j+2];
    const w=matrix[3]*px+matrix[7]*py+matrix[11]*pz+matrix[15];
    if(w<=0)continue;
    const nx=(matrix[0]*px+matrix[4]*py+matrix[8]*pz+matrix[12])/w;
    const ny=(matrix[1]*px+matrix[5]*py+matrix[9]*pz+matrix[13])/w;
    const nz=(matrix[2]*px+matrix[6]*py+matrix[10]*pz+matrix[14])/w;
    if(Math.abs(nx)>1||Math.abs(ny)>1||Math.abs(nz)>1)continue;
    const sx=(nx+1)*width/2,sy=(1-ny)*height/2;
    const distance=Math.hypot(sx-x,sy-y);
    const screenRadius=radius*sizes[id]*projectionY*height/(2*w);
    const score=Math.max(0,distance-screenRadius);
    if(id===previous)old={id,x:sx,y:sy,score,depth:w};
    if(!best||score<best.score-.25||(Math.abs(score-best.score)<=.25&&w<best.depth))best={id,x:sx,y:sy,score,depth:w};
  }
  // A little hysteresis prevents flickering between neighbours at rest.
  return old&&best&&old.score>0&&old.score<=best.score+3?old:best;
}

export const orbitPitch=(pitch,delta,scattered)=>Math.max(scattered?-Math.PI/2+.02:.06,Math.min(scattered?Math.PI/2-.02:.8,pitch+delta));
