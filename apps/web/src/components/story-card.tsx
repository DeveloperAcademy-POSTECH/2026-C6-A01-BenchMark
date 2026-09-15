/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
import type { Story } from "@/lib/story";

export function StoryCard({ story }: { story: Story }) {
  return <Link className="story-card" href={`/stories/${story.id}`}>
    <div className="card-photo"><img src={`/api/stories/${story.id}/photo?v=${story.revision}`} alt={`${story.display_name}님이 남긴 사진`} loading="lazy" /><span className="mat-number">자리 {String(story.mat_number).padStart(3, "0")}</span></div>
    <div className="card-copy"><p className="card-name">{story.display_name}<span>님의 이야기</span></p><p className="card-story">{story.story}</p><div className="card-bottom"><span>이야기 펼쳐보기 ↗</span><span aria-label={`공감 ${story.reaction_count}개`}>♡ {story.reaction_count}</span></div></div>
  </Link>;
}
