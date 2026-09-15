import { notFound } from "next/navigation";
import { getStory } from "@/lib/stories";
import { uuid } from "@/lib/story";
import { StoryReading } from "@/components/story-reading";
export const dynamic = "force-dynamic";

export default async function StoryPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!uuid.safeParse(id).success) notFound();
  const story = await getStory(id); if (!story) notFound();
  return <StoryReading story={story} />;
}
