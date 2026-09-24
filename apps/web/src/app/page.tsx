import { redirect } from "next/navigation";
import { listStories } from "@/lib/stories";
import { StoryReading } from "@/components/story-reading";
export const dynamic = "force-dynamic";

export default async function Home() {
  if (process.env.BENCHMARK_DESIGN_PREVIEW === "1") redirect("/concepts/editorial");
  const stories = await listStories();
  return <StoryReading story={stories[0]} donationButtonLabel="나도 기부 참가하기" />;
}
