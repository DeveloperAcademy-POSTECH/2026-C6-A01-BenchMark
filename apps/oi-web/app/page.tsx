import Image from "next/image";
import Link from "next/link";
export default function Home() {
  return <div className="oi-home oi-shell">
    <section className="oi-hero" aria-labelledby="home-title"><div className="oi-hero-copy"><span className="oi-kicker">오래 남는 이야기 기부</span><h1 id="home-title">당신의 이야기가<br />누군가의 <em>쉼</em>이 되도록.</h1><p>함께 웃던 날도, 고마웠던 마음도.<br />모교의 익숙한 벤치에 오래 남을 이야기를 전해요.</p><div className="oi-actions"><Link href="/donate" className="button primary">기부 시작하기 <span aria-hidden="true">↗</span></Link><a href="#how-it-works" className="oi-inline-link">오이기부 알아보기 ↓</a></div><span className="oi-caption">POSTECH의 기존 벤치에 이야기 명패와 NFC를 연결합니다.</span></div><div className="oi-hero-art"><Image src="/oi/bench.png" alt="나무 아래 놓인 벤치, 앱 디자인에 사용한 이미지" width={729} height={1096} priority /></div></section>
    <section className="oi-intro" id="how-it-works"><div><span className="oi-kicker">기부 그 이후까지</span><h2>마음은 남고,<br />이야기는 이어져요.</h2><p>새 벤치를 만드는 대신, 학교가 승인한 기존 벤치에<br className="oi-desktop-break" /> 명패와 이야기를 더하는 서비스입니다.</p></div><ol className="oi-steps"><li><span>01 / 마음을 남기고</span><h3>기부의 시작</h3><p>공식 기부 절차를 확인해요. 실제 약정과 납입은 학교의 절차를 따릅니다.</p></li><li><span>02 / 이야기를 담고</span><h3>벤치에 머무는 이야기</h3><p>장소와 문구를 검토하고, 승인된 벤치에 명패와 NFC로 이야기를 연결해요.</p></li><li><span>03 / 함께 이어가요</span><h3>일상에서 만나는 마음</h3><p>잠시 쉬어 가는 누군가가 이야기를 읽고, 또 다른 마음을 나눌 수 있도록.</p></li></ol></section>
    <section className="oi-link-grid" aria-label="서비스 바로가기"><Link href="/donate"><span className="oi-kicker">PARTICIPATE</span><h2>첫 마음을 전해볼까요? <span aria-hidden="true">↗</span></h2><p>기부 절차와 명패 참여 안내를 확인하세요.</p></Link><Link href="/stories"><span className="oi-kicker">STORIES</span><h2>먼저 남겨진 이야기 <span aria-hidden="true">↗</span></h2><p>돗자리 파일럿에서 함께 펼친 마음을 만나보세요.</p></Link></section>
  </div>;
}
