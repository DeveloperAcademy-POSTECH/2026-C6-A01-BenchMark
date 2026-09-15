import { listStories } from "@/lib/stories";
import { StoryCard } from "@/components/story-card";
import { Donation } from "@/components/donation";
export const dynamic = "force-dynamic";
export const metadata = { title: "모든 이야기" };

export default async function Stories() {
  const stories = await listStories();
  return <><section className="stories-section" id="stories"><div className="section-heading"><div><span className="eyebrow">함께 펼친 마음들</span><h1>이 자리에 담긴 이야기</h1></div><span className="count">{stories.length}개의 이야기</span></div><p className="section-description">잠시 앉아, 이 자리를 선물한 사람의 이야기를 만나보세요.</p>
    {stories.length ? <div className="story-grid">{stories.map((story) => <StoryCard key={story.id} story={story} />)}</div> : <div className="empty-state"><h2>첫 이야기를 펼칠 준비를 하고 있어요.</h2><p>운영진이 확인한 이야기가 곧 이곳에 담깁니다.</p></div>}
  </section><Donation /></>;
}
