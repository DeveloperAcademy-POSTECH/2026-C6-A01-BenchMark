/* eslint-disable @next/next/no-img-element */
import { listStories } from "@/lib/stories";
import { StoryCard } from "@/components/story-card";
import { Donation } from "@/components/donation";
export const dynamic = "force-dynamic";

export default async function Home() {
  const stories = await listStories();
  return <><section className="hero"><span className="eyebrow">POSTECH × KAIST · 포카전</span><h1><img className="brand-title" src="/brand/title.svg" alt="쉼, 펴 — 기부돗자리 대여 프로젝트" /></h1><p>돗자리를 펼치면,<br /><strong>누군가의 이야기가 시작돼요.</strong></p><a href="#stories" className="hero-jump">이야기 만나보기 <span aria-hidden="true">↓</span></a></section>
    <section className="stories-section" id="stories"><div className="section-heading"><div><span className="eyebrow">함께 펼친 마음들</span><h2>이 자리에 담긴 이야기</h2></div><span className="count">{stories.length}개의 이야기</span></div><p className="section-description">잠시 앉아, 이 자리를 선물한 사람의 이야기를 만나보세요.</p>
      {stories.length ? <div className="story-grid">{stories.map((story) => <StoryCard key={story.id} story={story} />)}</div> : <div className="empty-state"><h3>첫 이야기를 펼칠 준비를 하고 있어요.</h3><p>운영진이 확인한 이야기가 곧 이곳에 담깁니다.</p></div>}
    </section><Donation /></>;
}
