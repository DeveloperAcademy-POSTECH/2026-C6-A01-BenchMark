import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = {
  title: "BenchMark — 기억이 머무는 자리",
  description: "캠퍼스의 소중한 기억이 누군가의 쉼이 되도록. BenchMark의 기부 사전신청을 만나보세요.",
  robots: { index: false, follow: false },
};
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="ko"><body>{children}</body></html>;
}
