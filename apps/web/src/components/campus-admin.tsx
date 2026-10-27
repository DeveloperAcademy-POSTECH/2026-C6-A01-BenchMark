"use client";
import { useCallback, useEffect, useState } from "react";

type Oi={id:string;title:string;story:string;displayName:string;latitude:number;longitude:number;heightMeters:number;headingDegrees:number;status:string;revision:number;writerID:string;writerRevokedAt:string|null};
type Grant={id:string;created_at:string;redeemed_at:string|null;revoked_at:string|null};
  async function api(path:string,method="GET",data?:unknown) {
    const response=await fetch(path,{method,headers:{"Content-Type":"application/json"},body:data?JSON.stringify(data):undefined,cache:"no-store"});
    const body=await response.json();if(!response.ok)throw new Error(body.error||"요청에 실패했습니다.");return body;
  }

async function loadCampus() {
    const result:Oi[]=[];let cursor:string|null=null;
    do {const page=await api("/api/admin/campus/ois"+(cursor?"?cursor="+cursor:""));result.push(...page.items);cursor=page.nextCursor;if(result.length>10000)throw new Error("조회 범위가 큽니다. 운영진에게 문의해주세요.");}while(cursor);
    const writers=await api("/api/admin/campus/grants");return {items:result,grants:writers.items as Grant[]};
}
export function CampusAdmin() {
  const [items,setItems]=useState<Oi[]>([]),[grants,setGrants]=useState<Grant[]>([]),[code,setCode]=useState("");
  const [confirmed,setConfirmed]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState("");
  const refresh=useCallback(async () => {
    const data=await loadCampus();setItems(data.items);setGrants(data.grants);
  }, []);
  useEffect(()=>{
    let active=true;
    loadCampus().then(data=>{if(active){setItems(data.items);setGrants(data.grants);}}).catch(e=>{if(active)setError(e.message);});
    return ()=>{active=false;};
  },[]);
  async function action(work:()=>Promise<void>) {setBusy(true);setError("");try{await work();await refresh();}catch(e){setError(e instanceof Error?e.message:"처리하지 못했습니다.");}finally{setBusy(false);}}
  return <main className="admin-page campus-admin"><h1>캠퍼스 오이 관리</h1><p>돗자리 이야기와 별도로 관리합니다. 작성 승인은 팀의 증빙 검토 결과이며 학교 공식 확인·영수증 발급을 뜻하지 않습니다.</p>
    <fieldset disabled={busy}><h2>글 작성 권한 발급</h2><label><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)}/> 외부에서 증빙을 확인했고 이 이용자의 글 작성을 승인합니다.</label>
      <button className="button primary" disabled={!confirmed} onClick={()=>action(async()=>{const g=await api("/api/admin/campus/grants","POST",{reviewConfirmed:true});setCode(g.code);setConfirmed(false);})}>작성 코드 발급</button>
      {code&&<section role="status"><p>승인한 이용자에게만 전달하세요. 24시간 안에 한 번 등록할 수 있으며 앱의 작성 권한은 30일간 유효합니다. 이 화면을 떠나면 코드를 다시 볼 수 없습니다.</p><output style={{overflowWrap:"anywhere"}}>{code}</output><button onClick={()=>{void navigator.clipboard.writeText(code).catch(()=>setError("복사하지 못했습니다. 코드를 직접 선택해 복사해주세요."));}}>복사</button><button onClick={()=>setCode("")}>코드 숨기기</button></section>}
      {error&&<p role="alert" className="error-message">{error}</p>}<button onClick={()=>action(async()=>{})}>새로고침</button>
      <h2>오이·이야기 검토</h2>{!items.length&&<p>등록된 오이가 없습니다.</p>}
      {items.map(o=><article className="editor" key={o.id}><h3>{o.title} · {{pending:"공개 검토 대기",published:"공개 중",hidden:"비공개"}[o.status]||o.status}</h3><p>{o.displayName}</p><p style={{whiteSpace:"pre-wrap"}}>{o.story}</p><p>{o.latitude.toFixed(6)}, {o.longitude.toFixed(6)} · {o.heightMeters}m · {o.headingDegrees}°</p><small>작성 권한 ID: {o.writerID}</small><p>실제 공개 이용 가능한 장소인지와 내용·공개 이름을 검토해주세요.</p>
        <button disabled={!!o.writerRevokedAt} onClick={()=>action(async()=>{await api(`/api/admin/campus/ois/${o.id}`,"PUT",{status:"published",revision:o.revision});})}>검토 완료 · 공개</button>
        <button onClick={()=>action(async()=>{await api(`/api/admin/campus/ois/${o.id}`,"PUT",{status:"hidden",revision:o.revision});})}>비공개</button></article>)}
      <h2>최근 작성 권한 (최대 200개)</h2>{grants.map(g=><article key={g.id}><p>{g.id} · {g.revoked_at?"취소됨":g.redeemed_at?"앱 등록됨":"등록 대기"}</p><button disabled={!confirmed||!!g.revoked_at} onClick={()=>action(async()=>{const grant=await api("/api/admin/campus/grants","POST",{reviewConfirmed:true,writerID:g.id});setCode(grant.code);setConfirmed(false);})}>같은 작성자 코드 재발급</button><button disabled={!!g.revoked_at} onClick={()=>{if(window.confirm("작성 권한을 취소하고 해당 이용자의 공개 오이를 숨길까요?"))action(async()=>{await api(`/api/admin/campus/grants/${g.id}`,"DELETE");});}}>권한 취소·공개 중단</button></article>)}
    </fieldset></main>;
}
