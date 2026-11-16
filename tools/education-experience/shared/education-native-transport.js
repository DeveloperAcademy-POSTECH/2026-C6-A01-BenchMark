const waiting=new Map();
window.educationNativeReply=(id,result)=>{const task=waiting.get(id);if(!task)return;waiting.delete(id);clearTimeout(task.timer);if(result.ok)task.resolve(result.data);else task.reject(Error(result.error??'앱에서 요청을 처리하지 못했어요.'));};
export function nativeRequest(action,payload={}){
 const id=crypto.randomUUID();
 return new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>{waiting.delete(id);reject(Error('앱 응답을 확인하지 못했어요. 초안을 확인하고 다시 시도해 주세요.'));},90000);
  waiting.set(id,{resolve,reject,timer});window.webkit.messageHandlers.building.postMessage({kind:'education',id,action,...payload});
 });
}
export function createNativeTransport(){return {
 identity:()=>nativeRequest('identity'),rpc:(name,payload)=>nativeRequest('rpc',{name,payload}),media:path=>nativeRequest('media',{path}),
 async upload(path,blob){const buffer=new Uint8Array(await blob.arrayBuffer());let text='';for(let i=0;i<buffer.length;i+=16384)text+=String.fromCharCode(...buffer.subarray(i,i+16384));await nativeRequest('upload',{path,mime:blob.type,base64:btoa(text)});},
 login:()=>nativeRequest('login'),logout:()=>nativeRequest('logout')
};}
