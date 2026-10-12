import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import { currentAccount } from "@/lib/auth/server";
import { logout } from "@/app/login/actions";
import "./globals.css";
export const dynamic = "force-dynamic";
export const metadata: Metadata = {
  title: { default: "오이기부 — 오래 남는 이야기 기부", template: "%s | 오이기부" },
  description: "POSTECH의 익숙한 벤치에 마음과 이야기를 남기는 오이기부. 기부 안내와 함께 펼친 이야기를 만나보세요.",
};
export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const { user } = await currentAccount();
  return <html lang="ko"><body>
    <a href="#main" className="skip-link">본문으로 바로가기</a>
    <header className="site-header oi-header"><Link className="oi-brand" href="/" aria-label="오이기부 홈"><Image src="/oi/logo.png" alt="" width={42} height={38} /><Image src="/oi/wordmark.png" alt="오이기부" width={110} height={27} /></Link><nav aria-label="주 메뉴"><Link href="/stories">이야기</Link><Link href="/donate">기부 안내</Link>{user ? <form action={logout}><button className="oi-account-button">로그아웃</button></form> : <Link href="/login">로그인</Link>}</nav></header>
    <main id="main">{children}</main>
    <footer className="site-footer oi-footer"><div><Link href="/" className="oi-footer-name">오이기부</Link><p>한 사람의 마음이 벤치에 머물고,<br />그 자리에서 또 다른 이야기가 시작됩니다.</p></div><div><p>제작팀 · BenchMark</p><p className="academy">APPLE DEVELOPER ACADEMY @POSTECH</p><Link className="admin-link" href="/admin">파일럿 관리자</Link></div></footer>
  </body></html>;
}
