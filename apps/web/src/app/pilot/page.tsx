import { listStories } from "@/lib/stories";
import { StoryReading } from "@/components/story-reading";
export const dynamic = "force-dynamic";
export const metadata = { title: "쉼, 펴 파일럿" };
export default async function Pilot() {
  const stories = await listStories();
  return <StoryReading story={stories[0]} donationButtonLabel="나도 기부 참가하기" />;
}
