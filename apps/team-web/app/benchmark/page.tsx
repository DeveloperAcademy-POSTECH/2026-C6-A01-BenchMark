import type { Metadata } from "next";
import { BrandHome } from "@/components/brand/brand-home";

export const metadata: Metadata = {
  title: "BenchMark — 마음이 머무는 자리",
  description: "좋은 마음이 머무는 자리를 만듭니다. 기억과 기부를 함께 머무를 수 있는 공간으로 잇는 벤치마크.",
  robots: { index: false, follow: false },
};

export default function BenchMarkPage() { return <BrandHome />; }
