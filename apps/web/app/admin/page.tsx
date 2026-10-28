import { isAdmin } from "@/lib/security";
import { listStories } from "@/lib/stories";
import { AdminLogin } from "@/components/admin-login";
import { AdminDashboard } from "@/components/admin-dashboard";
import { listReservations } from "@/lib/reservations";
export const dynamic = "force-dynamic";
export const metadata = { title: "관리자", robots: { index: false, follow: false } };
export default async function Admin() {
  if (!await isAdmin()) return <AdminLogin />;
  const [stories, reservations] = await Promise.all([listStories(true), listReservations()]);
  return <AdminDashboard stories={stories} reservations={reservations} />;
}
