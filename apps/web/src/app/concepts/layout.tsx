import type { Metadata } from "next";

export const metadata: Metadata = {
  title: { default: "BenchMark — 디자인 프리뷰", template: "%s | BenchMark" },
  description: "마음이 머무는 자리, BenchMark. 메인 웹 디자인 방향을 비교하는 공개 초안입니다.",
  robots: { index: false, follow: false },
};
export default function ConceptsLayout({ children }: { children: React.ReactNode }) {
  return children;
}
