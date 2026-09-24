import Image from "next/image";
import type { Metadata } from "next";
import { Arrow, Footer, Photo, Switcher, pilotUrl } from "@/components/concepts/shared";
import s from "@/components/concepts/concepts.module.css";

export const metadata: Metadata = { title: "02 — Make room for good" };
export default function Immersive() {
  return <div className={`${s.root} ${s.immersive}`} id="top">
    <a href="#content" className={s.skip}>본문으로 바로가기</a>
    <div className={s.topSwitcher}><Switcher current="immersive" /></div>
    <section className={s.skyHero} aria-labelledby="immersive-title">
      <header className={s.boldHeader}><a href="#top" className={s.boldLogo}>B<span aria-hidden="true">↗</span> BENCHMARK</a><nav aria-label="주 메뉴"><a href="#about">Our purpose</a><a href="#projects">Projects</a><a href="#approach">Our approach</a></nav><a href={pilotUrl} className={s.whiteButton}>쉼, 펴 만나기 <Arrow /></a></header>
      <h1 className={s.massiveTitle} id="immersive-title">MAKE ROOM.</h1>
      <div className={s.heroSide}><span>FOR PEOPLE.<br />FOR MEMORIES.<br />FOR TOMORROW.</span><p>마음을 나누고,<br />머무를 자리를 만듭니다.</p><a href="#about" aria-label="벤치마크 소개로 이동">↓</a></div>
      <div className={s.floatingBench}><Image src="/concepts/bench-cutout.webp" alt="밝은 하늘 앞에 놓인 목재 벤치 디자인 콘셉트" fill sizes="(max-width: 700px) 110vw, 80vw" priority /></div>
      <div className={s.skyCaption}><span>좋은 마음이 놓일 자리.</span><span>BENCHMARK / DESIGN CONCEPT</span></div>
    </section>
    <main id="content" className={s.boldBody}>
      <section id="about" className={s.boldAbout}><div className={s.ruleHeading}><span>Ⓐ</span><span>ABOUT BENCHMARK</span></div><div className={s.boldIntro}><h2>SMALL GESTURES.<br />LASTING PLACES.</h2><div><h3>작은 마음이 모여,<br />오래 남을 공간으로.</h3><p>벤치마크는 기억이 있는 장소에 마음을 남기고, 그 마음이 누군가의 쉼으로 이어지는 경험을 만듭니다.</p></div><div><p>함께 앉을 자리를 만드는 일. 우리는 기부와 공간 사이에서 그 가능성을 탐색하고 있습니다.</p><a href="#projects" className={s.blackButton}>프로젝트 살펴보기 <Arrow /></a></div></div>
      <div className={s.boldPhotoGrid}><Photo /><div className={s.boldStatement}><span className={s.outlineLabel}>OUR STARTING POINT</span><strong>01<span>개의 작은 시작</span></strong><p>쉼, 펴에서 시작한 질문을<br />더 오래 머무는 공간으로.</p><span className={s.caption}>벤치 이미지는 미래 방향을 표현한 콘셉트입니다.</span></div></div></section>
      <section id="projects" className={s.boldProjects}><div className={s.ruleHeading}><span>Ⓑ</span><span>OUR PROJECT</span></div><div className={s.projectSplit}><div><span className={s.tag}>PILOT / 쉼, 펴</span><h2>TAKE A SEAT.<br />SHARE A STORY.</h2><p>쉬어가는 자리에서 만나는 누군가의 이야기.<br />작은 돗자리 하나로 시작한 우리의 첫 실험입니다.</p><a href={pilotUrl} className={s.blackButton}>쉼, 펴 웹사이트 방문 <Arrow /></a></div><a href={pilotUrl} className={s.bluePilot}><span>BENCHMARK PROJECT 001</span><strong>쉼,<br />펴<span>↗</span></strong><span>이야기가 머무는 자리</span></a></div></section>
      <section id="approach" className={s.boldApproach}><div className={s.ruleHeading}><span>Ⓒ</span><span>HOW WE THINK</span></div><h2>A PLACE.<br />A MEMORY.<br /><em>A NEW BEGINNING.</em></h2><div className={s.approachRows}><div><span>01 / 기억</span><p>마음이 머물렀던 장소에서 출발합니다.</p></div><div><span>02 / 연결</span><p>기부와 공간을 잇는 참여 방식을 고민합니다.</p></div><div><span>03 / 지속</span><p>다음 사람이 누릴 쉼과 그 이후를 생각합니다.</p></div></div></section>
    </main><Footer current="immersive" />
  </div>;
}
