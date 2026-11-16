const ORIGIN='https://postech-lights-together.wpwnshrck.chatgpt.site';
const PROJECT_URL='https://kfzfzarslqdqmrazohej.supabase.co';

// This endpoint returns public browser configuration only. It never reads a
// service-role key, session, database row or Storage object. RLS remains the
// authorization boundary; an Origin header is not a user identity.
export function handleWebConfig(request,env){
 const origin=request.headers.get('origin');
 if(origin!==ORIGIN)return new Response('Origin unavailable',{status:403});
 const headers={'Access-Control-Allow-Origin':ORIGIN,'Access-Control-Allow-Methods':'GET, OPTIONS','Access-Control-Allow-Headers':'content-type','Vary':'Origin','X-Content-Type-Options':'nosniff'};
 if(request.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(request.method!=='GET')return new Response('Method unavailable',{status:405,headers});
 const url=env('SUPABASE_URL'),key=env('SUPABASE_ANON_KEY');
 let valid=false;
 try{const claims=JSON.parse(atob(key.split('.')[1].replaceAll('-','+').replaceAll('_','/')));valid=claims.role==='anon'&&claims.ref==='kfzfzarslqdqmrazohej';}catch{}
 if(url!==PROJECT_URL||!valid)return new Response('Public configuration unavailable',{status:503,headers});
 return Response.json({url,publishableKey:key},{headers:{...headers,'Cache-Control':'public, max-age=300'}});
}
