import Image from "next/image";
import s from "./brand-home.module.css";

const pilotUrl = "https://mat-web-production.up.railway.app";
const sections = [
  ["belief", "OUR BELIEF"],
  ["pilot", "OUR FIRST PILOT"],
  ["tomorrow", "OUR TOMORROW"],
];

function SectionNav({ footer = false }: { footer?: boolean }) {
  return <nav className={`${s.sectionNav} ${footer ? s.footerNav : ""}`} aria-label={footer ? "하단 목차" : "페이지 목차"}>
    {sections.map(([id, label], index) => <a key={id} href={`#${id}`}><span>{index + 1}.</span><span>{label}</span><span aria-hidden="true">→</span></a>)}
  </nav>;
}
function SectionLabel({ index }: { index: number }) {
  return <p className={s.sectionLabel}>{index + 1}. <span>{sections[index][1]}</span></p>;
}
function Arrow() { return <span aria-hidden="true">→</span>; }

const values = [
  { label: "01  _  MEMORY", title: <>장소를 기억하는<br />사람들의 마음</>, body: <>마음이 머물렀던 장소에서 출발합니다.<br />어떤 장소가 나에게 소중한지 묻는 것에서 시작합니다.<br />공간의 의미는 그곳에 머물렀던 사람에게서 옵니다.</> },
  { label: "02  _  CONNECTION", title: <>마음을 전하는<br />구체적인 방법</>, body: <>기부와 공간을 잇는 참여 방식을 고민합니다.<br />좋은 뜻이 실제 공간과 연결되도록,<br />참여하는 사람과 공간을 운영하는 사람 사이의 과정을 고민합니다.</> },
  { label: "03  _  CONTINUITY", title: <>만드는 순간부터<br />그다음의 시간까지</>, body: <>다음 사람이 누릴 쉼과 그 이후를 생각합니다.<br />공간이 만들어진 뒤에도 의미가 이어질 수 있도록,<br />진행 과정과 이후의 돌봄까지 함께 생각합니다.</> },
];
const questions = [
  ["왜 공간에서 시작하나요?", "공간은 서로 다른 사람의 일상을 이어줍니다. 나에게 소중했던 장소가 다음 사람에게도 편안한 자리가 되기를 바랍니다."],
  ["쉼, 펴와 벤치마크는 어떤 관계인가요?", "‘쉼, 펴’는 벤치마크의 파일럿 프로젝트입니다. 메인 웹에서는 팀의 방향과 프로젝트를 소개하고, 기존 ‘쉼, 펴’ 웹에서는 파일럿의 이야기를 이어갑니다."],
  ["다음 프로젝트는 무엇인가요?", "기억과 기부가 실제 쉼의 공간으로 이어지는 경험을 구상하고 있습니다. 설치 장소와 일정, 참여 방식은 확정된 내용부터 안내할 예정입니다."],
];

export function BrandHome() {
  return <div className={s.page} id="top">
    <a href="#content" className="skip-link">본문으로 바로가기</a>
    <main id="content" tabIndex={-1}>
      <section className={s.hero} aria-labelledby="brand-title" data-node-id="436:812">
        <div className={s.heroBackdrop} aria-hidden="true"><div className={s.glowOne} /><div className={s.glowTwo} /><div className={s.glowThree} /></div>
        <h1 id="brand-title">BenchMark</h1>
        <p className={s.heroEnglish}>FOR PEOPLE,<br />FOR MEMORIES,<br />FOR TOMORROW.</p>
        <p className={s.heroKorean}>좋은 마음이<br />머무는 자리를 만듭니다</p>
        <Image className={s.bench} src="/brand/ffbb7.png" alt="함께 앉아 쉴 수 있는 나무 벤치" width={1244} height={708} priority unoptimized />
        <a className={`${s.pill} ${s.heroButton}`} href="#belief">벤치마크 알아보기 <Arrow /></a>
        <SectionNav />
      </section>
      <section className={s.belief} id="belief" aria-labelledby="belief-title" data-node-id="441:844">
        <SectionLabel index={0} />
        <h2 id="belief-title">누군가의 기억이<br />다른 누군가의<br /><span>쉼이 될 수 있도록.</span></h2>
        <div className={s.beliefCopy}>
          <p>기억이 남는 장소에는 늘 사람이 있습니다.<br />잠시 앉아 나눈 대화, 함께 보낸 오후...<br />그리고 오래 남은 마음.</p>
          <p>벤치마크는 그 마음을 기부와 연결하고,<br />함께 머무를 수 있는 공간으로 이어가는 방법을 찾습니다.</p>
          <a className={s.pill} href="#pilot">벤치마크의 첫 시작 살펴보기 <Arrow /></a>
        </div>
      </section>
      <section className={s.pilot} id="pilot" aria-labelledby="pilot-title" data-node-id="432:775">
        <div className={s.pilotCopy}>
          <SectionLabel index={1} />
          <h2 id="pilot-title">시작은,<br />작은 돗자리 하나.</h2>
          <p>‘쉼, 펴’는 누군가의 이야기가 담긴 돗자리를 펼치고, 그 위에서 쉬어가는 경험으로 출발했습니다.<br />이 작은 파일럿에서 시작한 이야기를, 더 오래 머무는 공간으로 이어가고 싶습니다.</p>
        </div>
        <div className={s.pilotCard} data-node-id="436:802">
          <Image src="/brand/12c1c.png" alt="쉼, 펴 — 기부돗자리 대여 프로젝트" width={513} height={200} unoptimized />
          <a className={s.pill} href={pilotUrl}>쉼,펴 프로젝트 살펴보기 <Arrow /></a>
        </div>
      </section>
      <section className={s.tomorrow} id="tomorrow" aria-labelledby="tomorrow-title" data-node-id="441:873">
        <SectionLabel index={2} />
        <h2 id="tomorrow-title">우리가 이어가려는 것</h2>
        <div className={s.values}>{values.map(value => <article key={value.label}>
          <p className={s.valueLabel}>{value.label}</p><h3>{value.title}</h3><p className={s.valueBody}>{value.body}</p>
        </article>)}</div>
        <div className={s.questions}>
          <h2>함께 써 내려갈<br />다음 이야기</h2>
          <div>{questions.map(([question, answer], index) => <details key={index} open>
            <summary>{question}<span className={s.chevron} aria-hidden="true" /></summary><p>{answer}</p>
          </details>)}</div>
        </div>
      </section>
      <section className={s.invitation} aria-labelledby="invitation-title">
        <p>NOW MAKE THING FOR GOOD.</p>
        <h2 id="invitation-title">다음 사람을 위한 자리를,<br />함께.</h2>
        <a className={s.pill} href={pilotUrl}>첫 번째 프로젝트 만나기 <Arrow /></a>
      </section>
    </main>
    <footer className={s.footer}>
      <div className={s.footerTop}>
        <a className={s.wordmark} href="#top">BenchMark<span>마음이 머무는 자리</span></a>
        <SectionNav footer />
      </div>
      <div className={s.credits}><span>© 2026 BenchMark</span><span>APPLE DEVELOPER ACADEMY @ POSTECH</span><span>DONNY　 EEPY　 JUN　 KAELYN　 SOORI　 SPERO</span></div>
    </footer>
  </div>;
}
