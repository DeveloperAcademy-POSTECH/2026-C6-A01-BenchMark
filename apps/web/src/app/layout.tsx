import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "쉼, 펴 — 돗자리 위에 펼쳐진 이야기", template: "%s | 쉼, 펴" },
  description: "포카전에서 펼쳐진 돗자리, 그 위에 담긴 아카데미 구성원의 사진과 이야기를 만나보세요.",
};
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="ko"><body>
    <a href="#main" className="skip-link">본문으로 바로가기</a>
    <header className="site-header"><Link className="wordmark" href="/" aria-label="쉼, 펴 홈">쉼, 펴<span>이야기가 머무는 자리</span></Link><nav aria-label="주 메뉴"><Link href="/">이야기</Link></nav></header>
    <main id="main">{children}</main>
    <footer className="site-footer"><p>하나의 이야기가, 다음 사람의 쉼으로.</p><p className="academy">APPLE DEVELOPER ACADEMY @POSTECH</p><Link className="admin-link" href="/admin">관리자 페이지</Link></footer>
  </body></html>;
}
