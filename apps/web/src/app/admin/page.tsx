import { isAdmin } from "@/lib/security";
import { listStories } from "@/lib/stories";
import { AdminLogin } from "@/components/admin-login";
import { AdminDashboard } from "@/components/admin-dashboard";
export const dynamic = "force-dynamic";
export const metadata = { title: "관리자", robots: { index: false, follow: false } };
export default async function Admin() {
  if (!await isAdmin()) return <AdminLogin />;
  return <AdminDashboard stories={await listStories(true)} />;
}
