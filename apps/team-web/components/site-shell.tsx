"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

export function SiteShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  if (pathname === "/benchmark" || pathname === "/concepts" || pathname.startsWith("/concepts/")) return children;
  return <>
    <a href="#main" className="skip-link">본문으로 바로가기</a>
    <header className="site-header"><Link className="wordmark" href="/" aria-label="쉼, 펴 홈">쉼, 펴<span>이야기가 머무는 자리</span></Link><nav aria-label="주 메뉴"><Link href="/">이야기</Link></nav></header>
    <main id="main">{children}</main>
    <footer className="site-footer"><p>하나의 이야기가, 다음 사람의 쉼으로.</p><p className="academy">APPLE DEVELOPER ACADEMY @POSTECH</p><Link className="admin-link" href="/admin">관리자 페이지</Link></footer>
  </>;
}
