import Link from "next/link";
import { isAdmin } from "@/lib/security";
import { AdminLogin } from "@/components/admin-login";
import { CampusAdmin } from "@/components/campus-admin";
export const dynamic="force-dynamic";
export const metadata={title:"캠퍼스 오이 관리",robots:{index:false,follow:false}};
export default async function Page(){if(!await isAdmin())return <AdminLogin/>;return <><Link href="/admin">돗자리 관리로 돌아가기</Link><CampusAdmin/></>;}
