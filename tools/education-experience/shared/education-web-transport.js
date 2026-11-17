import {createClient} from '@supabase/supabase-js';
import {fetchReferenceCatalog} from './education-service.js';
const URL='https://kfzfzarslqdqmrazohej.supabase.co';
export async function createWebTransport(onChange){
 const response=await fetch(URL+'/functions/v1/oi-web-config',{cache:'no-cache'});
 if(!response.ok)throw Error('이야기 서버에 연결하지 못했어요. 잠시 후 다시 시도해 주세요.');
 const config=await response.json();
 let claims;try{claims=JSON.parse(atob(config.publishableKey.split('.')[1].replaceAll('-','+').replaceAll('_','/')));}catch{}
 if(config.url!==URL||claims?.role!=='anon'||claims?.ref!=='kfzfzarslqdqmrazohej')throw Error('서버 공개 설정을 확인하지 못했어요.');
 const client=createClient(config.url,config.publishableKey,{auth:{flowType:'pkce',storage:sessionStorage,storageKey:'oi-education-auth-v1',detectSessionInUrl:true,persistSession:true,autoRefreshToken:true}});
 let authUser;
 client.auth.onAuthStateChange((event,session)=>{
  const next=session?.user?.id??null;
  if(event==='INITIAL_SESSION'){authUser=next;return;}
  if(['SIGNED_IN','SIGNED_OUT','USER_UPDATED'].includes(event)){const changed=next!==authUser;authUser=next;if(changed||event==='USER_UPDATED')setTimeout(onChange,0);}
 });
 const {error}=await client.auth.getSession();if(error)throw Error('로그인을 다시 진행해 주세요. 저장한 초안은 남아 있어요.');
 async function check(result){const {data,error}=await result;if(error){const e=Error(error.message??'서버 요청에 실패했어요.');e.code=error.code;throw e;}return data;}
 return {
  catalog:fetchReferenceCatalog,
  async identity(){const {data:{session}}=await client.auth.getSession();if(!session)return {id:null,operator:false,canWrite:false};const caps=await check(client.rpc('oi_capabilities',{}));return {id:caps.account_id,operator:caps.operator===true,canWrite:caps.independent_story_creation===true&&caps.unapproved_drafts_enabled===true};},
  rpc:(name,payload)=>check(client.rpc(name,payload)),
  moderate:(id,revision)=>check(client.functions.invoke('moderate-story',{body:{scope:'education',id,revision,ai_review_consent_version:1}})),
  async media(path){const data=await check(client.storage.from('oi-story-media').createSignedUrl(path,300));return data.signedUrl;},
  async upload(path,blob){
   const result=await client.storage.from('oi-story-media').upload(path,blob,{contentType:blob.type,upsert:false});
   if(!result.error)return;
   // A lost response or repeated upload must never overwrite existing artwork.
   const old=await check(client.storage.from('oi-story-media').download(path));
   const hash=async value=>new Uint8Array(await crypto.subtle.digest('SHA-256',await value.arrayBuffer()));
   const [a,b]=await Promise.all([hash(blob),hash(old)]);if(a.length!==b.length||!a.every((v,i)=>v===b[i]))throw Error('같은 경로에 다른 이미지가 있어요. 초안을 보존했으니 다시 저장해 주세요.');
  },
  async login(provider){await check(client.auth.signInWithOAuth({provider,options:{redirectTo:location.origin+'/'}}));},
  async logout(){await check(client.auth.signOut({scope:'local'}));}
 };
}
