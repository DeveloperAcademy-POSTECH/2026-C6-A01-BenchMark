import Image from "next/image";
import type { Metadata } from "next";
import { Arrow, Footer, Photo, Switcher, pilotUrl } from "@/components/concepts/shared";
import s from "@/components/concepts/concepts.module.css";

export const metadata: Metadata = { title: "03 — 내일의 누군가에게" };
export default function Tomorrow() {
  return <div className={`${s.root} ${s.tomorrow}`} id="top">
    <a href="#content" className={s.skip}>본문으로 바로가기</a>
    <div className={s.topSwitcher}><Switcher current="tomorrow" /></div>
    <header className={s.tomorrowHeader}><a href="#top" className={s.tomorrowLogo}><span aria-hidden="true">bm.</span> BenchMark,</a><nav aria-label="주 메뉴"><a href="#about">우리의 생각</a><a href="#beginning">작은 시작</a><a href="#questions">다음 이야기</a></nav><a href={pilotUrl} className={s.creamButton}>쉼, 펴 방문 <Arrow /></a></header>
    <main id="content">
      <section className={s.tomorrowHero}><span className={s.tag}>DEAR SOMEONE, SOMEWHERE, TOMORROW.</span><Photo priority /><div className={s.tomorrowHeroCopy}><h1>오늘 우리가 남긴 마음이,<br />내일 누군가의<br /><em>쉬어갈 자리가 된다면.</em></h1><p>사람과 기억, 그리고 공간을 잇는 작은 시작.<br />우리는 벤치마크입니다.</p><a href="#about" aria-label="벤치마크의 생각 읽기">↓</a></div></section>
      <section id="about" className={s.tomorrowAbout}><div className={s.letterPhoto}><Image src="/concepts/letter-table.webp" alt="나무 테이블에서 편지를 쓰는 손을 표현한 콘셉트 이미지" fill sizes="(max-width: 700px) 100vw, 55vw" /></div><div><span className={s.tag}>A THOUGHT WORTH SHARING</span><h2>마음은 보이지 않지만,<br />머물 자리는<br />만들 수 있으니까.</h2><p>누군가와 나란히 앉았던 시간, 익숙한 캠퍼스의 풍경, 아무 말 없이 쉬어가던 오후. 우리가 기억하는 장소에는 저마다의 이야기가 있습니다.</p><p>벤치마크는 그 기억을 나누고, 기부를 통해 다른 사람을 위한 공간으로 이어가는 방법을 고민합니다.</p></div></section>
      <section className={s.tomorrowLetter}><span>TO THE NEXT PERSON WHO SITS HERE,</span><p>이 자리에 앉을 당신에게.<br />잠시 숨을 고르고,<br />좋아하는 풍경을 바라보세요.<br /><em>누군가의 마음이<br />당신의 쉼 곁에 있습니다.</em></p><span className={s.letterSignature}>With care, BenchMark</span><span className={s.letterNote}>벤치마크가 전하고 싶은 마음을 담은 브랜드 메시지입니다.</span></section>
      <section id="beginning" className={s.tomorrowBeginning}><div><span className={s.tag}>OUR FIRST CHAPTER</span><h2>시작은,<br />작은 돗자리 하나.</h2><p>쉼, 펴는 누군가의 이야기가 담긴 돗자리를 펼치고, 그 위에서 쉬어가는 경험으로 출발했습니다.</p><p>이 작은 파일럿에서 시작한 질문을, 더 오래 머무는 공간으로 이어가고 싶습니다.</p><a href={pilotUrl} className={s.purpleButton}>쉼, 펴 프로젝트 만나기 <Arrow /></a></div><div className={s.letterProject}><span>CHAPTER 01 / PILOT</span><strong>쉼, 펴</strong><p>하나의 이야기가,<br />다음 사람의 쉼으로.</p><span>FROM A SMALL MOMENT<br />TO A SHARED PLACE</span></div></section>
      <section id="questions" className={s.tomorrowQuestions}><span className={s.tag}>THE STORY WE WANT TO WRITE</span><h2>함께 써 내려갈<br />다음 이야기.</h2><div className={s.questionList}><details open><summary>왜 공간에서 시작하나요?<span aria-hidden="true">+</span></summary><p>공간은 서로 다른 사람의 일상을 이어줍니다. 나에게 소중했던 장소가 다음 사람에게도 편안한 자리가 되기를 바랍니다.</p></details><details><summary>쉼, 펴와 벤치마크는 어떤 관계인가요?<span aria-hidden="true">+</span></summary><p>쉼, 펴는 벤치마크의 파일럿 프로젝트입니다. 메인 웹에서는 팀의 방향과 프로젝트를 소개하고, 기존 쉼, 펴 웹에서는 파일럿의 이야기를 이어갑니다.</p></details><details><summary>앞으로 어떤 자리를 만들고 싶나요?<span aria-hidden="true">+</span></summary><p>기억과 기부가 실제 쉼의 공간으로 이어지는 경험을 구상하고 있습니다. 설치 장소와 일정, 참여 방식은 확정된 내용부터 안내할 예정입니다.</p></details></div></section>
      <section className={s.tomorrowClosing}><p>The next chapter begins with us.</p><h2>마음이 이어지면,<br />풍경도 달라집니다.</h2><a href={pilotUrl} className={s.purpleButton}>우리의 첫 이야기 읽기 <Arrow /></a></section>
    </main><Footer current="tomorrow" />
  </div>;
}
