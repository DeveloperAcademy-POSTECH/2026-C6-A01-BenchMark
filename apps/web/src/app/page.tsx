import { listStories } from "@/lib/stories";
import { StoryReading } from "@/components/story-reading";
export const dynamic = "force-dynamic";

export default async function Home() {
  const stories = await listStories();
  return <StoryReading story={stories[0]} donationButtonLabel="나도 기부 참가하기" />;
}
