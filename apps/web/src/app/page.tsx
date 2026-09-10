import { RegistrationForm } from "@/components/registration-form";
import { collectionPolicy } from "@/lib/config";
export const dynamic = "force-dynamic";

function BenchScene() {
  return <svg className="bench-scene" viewBox="0 0 720 620" role="img" aria-label="나무 그늘 아래 놓인 벤치의 일러스트. 실제 설치 장소가 아닌 서비스 이미지입니다.">
    <defs><linearGradient id="sky" x2="0" y2="1"><stop stopColor="#e5e9db"/><stop offset="1" stopColor="#f1eddd"/></linearGradient><linearGradient id="wood" x2="0" y2="1"><stop stopColor="#b77946"/><stop offset="1" stopColor="#855434"/></linearGradient><filter id="shadow"><feGaussianBlur stdDeviation="14"/></filter></defs>
    <rect width="720" height="620" fill="url(#sky)"/>
    <circle cx="533" cy="150" r="78" fill="#fff9dc" opacity=".8"/>
    <path d="M0 361Q135 292 289 338T720 333V620H0Z" fill="#bec8a8"/>
    <path d="M0 440Q167 326 394 436T720 401V620H0Z" fill="#9dad87"/>
    <path d="M165 620Q275 468 540 410L720 437Q444 467 355 620Z" fill="#ded7bd"/>
    <path d="M75 0L104 427L123 430L106 0Z" fill="#6a7055"/>
    <path d="M87 220L7 97M100 158L209 44" stroke="#6a7055" strokeWidth="18"/>
    <g fill="#758567"><ellipse cx="65" cy="50" rx="146" ry="94"/><ellipse cx="172" cy="32" rx="140" ry="75"/><ellipse cx="18" cy="152" rx="97" ry="89"/></g>
    <g fill="#8e9e7c"><ellipse cx="247" cy="26" rx="112" ry="54"/><ellipse cx="121" cy="107" rx="86" ry="63"/></g>
    <ellipse cx="419" cy="486" rx="193" ry="26" fill="#4e5e46" opacity=".25" filter="url(#shadow)"/>
    <g stroke="#37483d" strokeWidth="12" strokeLinecap="round"><path d="M279 360L274 476M498 335L524 452M310 421L299 491M546 397L565 466"/></g>
    <g fill="url(#wood)" stroke="#714d33" strokeWidth="2"><path d="M252 328L505 300L511 325L255 354Z"/><path d="M257 363L514 335L519 360L261 390Z"/><path d="M262 400L522 369L566 398L303 433Z"/><path d="M303 441L567 407L567 420L302 455Z"/></g>
    <rect x="354" y="327" width="47" height="16" rx="2" fill="#dfc493" transform="rotate(-6 354 327)"/>
    <g fill="#5f7456"><path d="M175 480q-30-36-31-6q4 18 31 6M177 481q20-43 29-18q-1 17-29 18M635 461q-23-45-35-18q0 20 35 18"/></g>
    <path d="M178 497L175 461M636 480L630 451" stroke="#5f7456" strokeWidth="3"/>
  </svg>;
}

export default function Home() {
  const policy = collectionPolicy();
  return <>
    <a className="skip-link" href="#main">본문으로 바로가기</a>
    <header className="site-header"><a className="wordmark" href="#" aria-label="BenchMark 홈">BenchMark<span className="brand-dot">.</span></a><nav aria-label="주요 메뉴"><a href="#about">우리의 이야기</a><a className="nav-cta" href="#apply">사전신청 <span aria-hidden="true">↗</span></a></nav></header>
    <main id="main">
      <section className="hero" aria-labelledby="hero-title">
        <div className="hero-copy"><p className="eyebrow"><span className="tiny-line"/> A PLACE FOR YOUR MEMORIES</p><h1 id="hero-title">기억이 머물던 곳에,<br/><em>마음을 놓아두세요.</em></h1><p className="hero-description">함께 웃던 날도, 잠시 쉬어가던 순간도.<br/>캠퍼스의 소중한 기억이<br className="mobile-break"/> 누군가의 쉼이 될 수 있도록.</p><a className="button" href="#apply">기부 사전신청하기 <span aria-hidden="true">↗</span></a><p className="hero-note">POSTECH에서 시작하는, BenchMark</p></div>
        <div className="hero-art"><BenchScene/><div className="art-caption"><span>YOUR MEMORY, SOMEONE’S REST.</span><span>01 — POSTECH</span></div><span className="art-label">기억을 잇는 작은 자리</span></div>
      </section>
      <section className="story section-shell" id="about" aria-labelledby="story-title"><div><p className="eyebrow">OUR STORY</p><h2 id="story-title">지나온 시간은,<br/>다음 사람의<br/><span className="muted-green">쉼이 됩니다.</span></h2></div><div className="story-body"><p className="lead">여러분의 캠퍼스에는<br/>어떤 기억이 남아 있나요?</p><p>수업 사이 나누던 대화, 늦은 밤 함께 걷던 길.<br/>평범했던 장소는 우리가 함께한 시간으로 특별해집니다.</p><p>BenchMark는 그 마음을 벤치라는 작은 공간에<br/>이어보려 합니다. 나의 기억을 남기고,<br/>다음 사람에게는 쉬어갈 자리를 건네는 기부입니다.</p><span className="story-signature">작은 자리에서 시작되는, 오래 남을 마음.</span></div></section>
      <section className="journey section-shell" aria-labelledby="journey-title"><div className="section-heading"><div><p className="eyebrow">HOW IT BEGINS</p><h2 id="journey-title">마음이 자리가 되기까지</h2></div><p>지금은 첫걸음을 함께할 분들을 만나고 있어요.</p></div><div className="steps">{[
        ["01", "마음을 남겨주세요", "이름과 연락처로 관심을 남겨주세요. 사전신청은 실제 기부금 납부가 아니에요."],
        ["02", "참여 방법을 준비해요", "기관과 장소·참여 절차를 협의하고 있어요. 확정된 내용으로 안내를 준비할게요."],
        ["03", "기억을 공간으로 이어요", "기부가 캠퍼스의 쉼으로 이어질 수 있도록, 벤치 조성과 이야기의 경험을 만들어갑니다."],
      ].map(([number, title, description]) => <article className="step" key={number}><span className="step-number">{number}</span><h3>{title}</h3><p>{description}</p></article>)}</div></section>
      <section className="apply-section" id="apply" aria-labelledby="apply-title"><div className="apply-inner"><div className="apply-copy"><p className="eyebrow">LEAVE YOUR INTEREST</p><h2 id="apply-title">당신의 마음이,<br/>첫 번째 시작입니다.</h2><p>캠퍼스에 남기고 싶은 마음이 있다면<br/>BenchMark의 시작을 함께해주세요.</p><div className="apply-aside"><span aria-hidden="true">↗</span><p>장소와 참여 일정은 준비 중입니다.<br/>사전신청만으로 기부가 확정되거나<br/>결제가 발생하지 않습니다.</p></div>{policy.mode === "test" && <p className="test-notice">현재는 팀 내부 테스트 단계입니다.<br/>실제 기부 접수와 연락은 진행하지 않습니다.</p>}</div><RegistrationForm testMode={policy.mode === "test"} retentionDays={policy.retentionDays} contact={policy.contact}/></div></section>
      <section className="faq section-shell" aria-labelledby="faq-title"><div><p className="eyebrow">GOOD TO KNOW</p><h2 id="faq-title">궁금한 이야기</h2></div><div className="faq-items"><details><summary>사전신청하면 바로 기부금이 결제되나요?</summary><p>아니요. 관심을 남기는 단계이며 결제는 진행되지 않습니다. 실제 기부 절차는 기관과 협의한 뒤 안내할 예정입니다.</p></details><details><summary>벤치는 어디에 설치되나요?</summary><p>POSTECH 캠퍼스를 시작으로 준비 중입니다. 구체적인 설치 장소와 일정은 확정되지 않았으며, 사전신청은 설치를 보장하지 않습니다.</p></details><details><summary>신청 후 정보를 수정하고 싶어요.</summary><p>{policy.mode === "test" ? "현재는 테스트 정보만 접수합니다. 같은 번호로 다시 제출해도 기존 정보는 덮어쓰지 않으며, 테스트 정보는 7일 보관 대상으로 관리합니다." : <>정보 수정·철회는 <a href={`mailto:${policy.contact}`}>{policy.contact}</a>로 문의해주세요.</>}</p></details></div></section>
    </main><footer className="site-footer"><a className="wordmark" href="#">BenchMark<span className="brand-dot">.</span></a><p>기억을 남기고, 쉼을 건네다.</p><span>© {new Date().getFullYear()} BenchMark Team</span></footer>
  </>;
}
