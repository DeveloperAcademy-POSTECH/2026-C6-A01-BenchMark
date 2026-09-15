import { listStories } from "@/lib/stories";
import { StoryReading } from "@/components/story-reading";
export const dynamic = "force-dynamic";

export default async function Home() {
  const stories = await listStories();
  return <StoryReading story={stories[0]} />;
}
