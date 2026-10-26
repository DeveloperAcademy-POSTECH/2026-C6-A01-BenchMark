import type { Metadata } from "next";
import { SiteShell } from "@/components/site-shell";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "쉼, 펴 — 돗자리 위에 펼쳐진 이야기", template: "%s | 쉼, 펴" },
  description: "포카전에서 펼쳐진 돗자리, 그 위에 담긴 아카데미 구성원의 사진과 이야기를 만나보세요.",
};
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="ko"><body><SiteShell>{children}</SiteShell></body></html>;
}
