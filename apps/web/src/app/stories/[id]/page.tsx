/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
import { notFound } from "next/navigation";
import { getStory } from "@/lib/stories";
import { uuid } from "@/lib/story";
import { Reaction } from "@/components/reaction";
import { Donation } from "@/components/donation";
export const dynamic = "force-dynamic";
export default async function StoryPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!uuid.safeParse(id).success) notFound();
  const story = await getStory(id); if (!story) notFound();
  return <div className="story-reading"><div className="reading-brand"><img src="/brand/title.svg" alt="쉼, 펴" /></div><article className="story-detail"><div className="story-paper"><div className="donor-intro"><span className="eyebrow">자리 {String(story.mat_number).padStart(3, "0")} · {story.display_name}님의 선물</span><p>이 돗자리에 담긴 마음</p><h1>{story.title || `${story.display_name}님이 펼친 이야기`}</h1><p>당신의 쉼과 함께 펼쳐집니다.</p></div><img className="detail-photo" src={`/api/stories/${id}/photo?v=${story.revision}`} alt={`${story.display_name}님이 남긴 사진`} /><div className="story-letter"><p>{story.story}</p><span>이 자리를 선물한 {story.display_name} 드림</span></div></div><Reaction key={id} id={id} /><section className="usage-guide"><span className="eyebrow">우리의 쉼이 오래 이어지도록</span><h2>사용 안내서</h2><ol><li>이 돗자리는 애플디벨로퍼아카데미 5기 러너들의 기부를 통해 마련한 돗자리입니다!<br /><strong>깨끗하게 사용 부탁드립니다!</strong></li><li>반납 시 운영진에게 돌아오셔서 <strong>성함 확인 후 반납</strong> 부탁드립니다!</li><li>문의사항이나 필요사항이 있으시면 운영진 부스에 문의 부탁드립니다!</li></ol></section><Donation sourceStoryId={id} /><Link className="text-link" href="/#stories">다른 자리의 이야기도 만나보기 →</Link></article></div>;
}
