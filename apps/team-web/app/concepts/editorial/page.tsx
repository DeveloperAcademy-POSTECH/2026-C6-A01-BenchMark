import type { Metadata } from "next";
import { Arrow, Footer, Photo, Switcher, pilotUrl } from "@/components/concepts/shared";
import s from "@/components/concepts/concepts.module.css";

export const metadata: Metadata = { title: "01 — 마음이 머무는 자리" };
export default function Editorial() {
  return <div className={`${s.root} ${s.editorial}`} id="top">
    <a href="#content" className={s.skip}>본문으로 바로가기</a>
    <div className={s.topSwitcher}><Switcher current="editorial" /></div>
    <div className={s.editorialHero}>
      <header className={s.editorialRail}>
        <a href="#top" className={s.serifLogo} aria-label="BenchMark 홈">Bench<br />Mark<span>마음이 머무는 자리</span></a>
        <nav aria-label="주 메뉴"><a href="#about">벤치마크의 생각 <Arrow /></a><a href="#projects">우리의 프로젝트 <Arrow /></a><a href="#journal">함께 만드는 변화 <Arrow /></a></nav>
        <div className={s.railBottom}><span>SMALL GESTURES.<br />LASTING PLACES.</span><div className={s.benchMark} aria-hidden="true"><i /><i /><i /></div><span>MEMORIES — PLACES<br />A PLACE FOR ALL OF US</span></div>
      </header>
      <section className={s.editorialCover} aria-labelledby="editorial-title">
        <Photo priority />
        <div className={s.coverShade} />
        <span className={s.coverLabel}>BENCHMARK / OUR VISION</span>
        <div className={s.coverCopy}><p>한 사람의 마음이, 모두의 공간으로.</p><h1 id="editorial-title">좋은 마음이<br />머무는 자리를<br />만듭니다.</h1><a href="#about" className={s.roundLink}>벤치마크 알아보기 <Arrow /></a></div>
        <span className={s.imageNote}>미래의 쉼을 그린 콘셉트 이미지</span>
      </section>
    </div>
    <main id="content">
      <section className={s.editorialIntro} id="about"><div className={s.sectionTag}>01 / OUR BELIEF</div><h2>누군가의 기억이<br />다른 누군가의<br /><em>쉼이 될 수 있도록.</em></h2><div className={s.introAside}><p>기억에 남는 장소에는 늘 사람이 있습니다. 잠시 앉아 나눈 대화, 함께 보낸 오후, 그리고 오래 남은 마음.</p><p>벤치마크는 그 마음을 기부와 연결하고, 함께 머무를 수 있는 실제 공간으로 이어가는 방법을 찾습니다.</p><a href="#projects" className={s.underLink}>우리의 첫걸음 보기 <Arrow /></a></div></section>
      <section className={s.editorialProjects} id="projects"><div className={s.sectionHeading}><h2>마음에서 시작된 일들</h2><span>OUR PROJECTS / 01</span></div><a href={pilotUrl} className={s.pilotFeature}><div className={s.pilotArtwork}><span>쉬어가는 마음을 펼치다</span><strong>쉼, 펴</strong><span className={s.pilotArtworkBottom}>A LITTLE REST.<br />A SHARED STORY.</span><span className={s.matArt} aria-hidden="true" /></div><div className={s.pilotDescription}><span className={s.tag}>PILOT PROJECT</span><h3>작은 돗자리에서<br />시작된 이야기.</h3><p>누군가의 이야기가 담긴 돗자리 위에서 잠시 쉬어가는 경험. 쉼, 펴는 마음을 나누는 방식을 탐색한 벤치마크의 파일럿 프로젝트입니다.</p><span className={s.underLink}>쉼, 펴 웹사이트 방문 <Arrow /></span></div></a></section>
      <section className={s.editorialJournal} id="journal"><div className={s.sectionHeading}><h2>우리가 이어가려는 것</h2><span>IDEAS FOR TOMORROW</span></div><div className={s.ideaGrid}><article><span>01 — MEMORY</span><h3>장소를 기억하는<br />사람들의 마음</h3><p>어떤 장소가 나에게 소중한지 묻는 것에서 시작합니다. 공간의 의미는 그곳에 머물렀던 사람에게서 옵니다.</p></article><article><span>02 — CONNECTION</span><h3>마음을 전하는<br />구체적인 방법</h3><p>좋은 뜻이 실제 공간과 연결되도록, 참여하는 사람과 공간을 운영하는 사람 사이의 과정을 고민합니다.</p></article><article><span>03 — CONTINUITY</span><h3>만드는 순간부터<br />그다음의 시간까지</h3><p>공간이 만들어진 뒤에도 의미가 이어질 수 있도록, 진행 과정과 이후의 돌봄까지 함께 생각합니다.</p></article></div></section>
      <section className={s.editorialClosing}><span>LET’S MAKE ROOM FOR GOOD.</span><h2>다음 사람을 위한 자리를,<br />함께.</h2><a href={pilotUrl} className={s.roundLink}>첫 번째 프로젝트 만나기 <Arrow /></a></section>
    </main><Footer current="editorial" />

  </div>;
}
