/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
import { notFound } from "next/navigation";
import { getStory } from "@/lib/stories";
import { sizes, uuid } from "@/lib/story";
import { Reaction } from "@/components/reaction";
import { Donation } from "@/components/donation";
export const dynamic = "force-dynamic";

export default async function StoryPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!uuid.safeParse(id).success) notFound();
  const story = await getStory(id); if (!story) notFound();
  return <><article className="story-detail"><Link className="back-link" href="/">← 모든 이야기</Link><div className="detail-heading"><span className="eyebrow">당신이 앉은 이 자리</span><p className="detail-number">자리 {String(story.mat_number).padStart(3, "0")}<span>{sizes[story.mat_size].label}</span></p><h1>{story.display_name}<span>님이 펼친 이야기</span></h1></div><div className="story-paper"><img className="detail-photo" src={`/api/stories/${id}/photo?v=${story.revision}`} alt={`${story.display_name}님이 남긴 사진`} /><div className="story-letter"><p>{story.story}</p><span>이 자리를 선물한 {story.display_name} 드림</span></div></div><Reaction key={id} id={id} initialCount={story.reaction_count} /><Link className="button secondary" href="/#stories">다른 자리의 이야기도 만나보기 →</Link></article><Donation /></>;
}
