import test from 'node:test';
import assert from 'node:assert/strict';
import {handleWebConfig} from '../functions/oi-web-config/handler.mjs';
const origin='https://postech-lights-together.wpwnshrck.chatgpt.site';
const key='e30.'+Buffer.from(JSON.stringify({role:'anon',ref:'kfzfzarslqdqmrazohej'})).toString('base64url')+'.synthetic';
const values={SUPABASE_URL:'https://kfzfzarslqdqmrazohej.supabase.co',SUPABASE_ANON_KEY:key};
test('only public configuration is returned to the specific website origin',async()=>{
 const requested=[];const r=handleWebConfig(new Request('https://example.test',{headers:{Origin:origin}}),name=>{requested.push(name);return values[name];});
 assert.equal(r.status,200);assert.deepEqual(await r.json(),{url:values.SUPABASE_URL,publishableKey:key});
 assert.deepEqual(requested,['SUPABASE_URL','SUPABASE_ANON_KEY']);assert.equal(r.headers.get('access-control-allow-origin'),origin);
});
test('preflight, unknown origins and methods do not expose keys',()=>{
 const env=()=>{throw Error('No environment access expected');};
 assert.equal(handleWebConfig(new Request('https://example.test',{method:'OPTIONS',headers:{Origin:origin}}),env).status,204);
 assert.equal(handleWebConfig(new Request('https://example.test',{headers:{Origin:'https://elsewhere.test'}}),env).status,403);
 assert.equal(handleWebConfig(new Request('https://example.test'),env).status,403);
 assert.equal(handleWebConfig(new Request('https://example.test',{method:'POST',headers:{Origin:origin}}),env).status,405);
});
test('privileged, missing and wrong-project keys fail closed',()=>{
 for(const bad of ['sb_secret_synthetic','', 'e30.'+Buffer.from(JSON.stringify({role:'service_role',ref:'kfzfzarslqdqmrazohej'})).toString('base64url')+'.x']){
  const r=handleWebConfig(new Request('https://example.test',{headers:{Origin:origin}}),name=>name==='SUPABASE_ANON_KEY'?bad:values[name]);assert.equal(r.status,503);
 }
});
