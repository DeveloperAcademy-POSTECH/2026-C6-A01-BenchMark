import { ReservationForm } from "@/components/reservation-form";
import { uuid } from "@/lib/story";
export const metadata = { title: "기부 예약" };
export default async function Reserve({ searchParams }: { searchParams: Promise<{ from?: string }> }) {
  const { from } = await searchParams;
  return <ReservationForm sourceStoryId={uuid.safeParse(from).success ? from : undefined} />;
}
