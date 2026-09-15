import { uuid } from "@/lib/story";
import { CameraExperience } from "@/components/camera/camera-experience";
export const metadata = { title: "캐릭터와 사진 찍기" };
export default async function CameraPage({ searchParams }: { searchParams: Promise<{ from?: string }> }) {
  const { from } = await searchParams;
  return <CameraExperience sourceStoryId={uuid.safeParse(from).success ? from : undefined} />;
}
