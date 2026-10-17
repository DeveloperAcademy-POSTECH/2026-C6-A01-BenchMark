import Image from "next/image";
import Link from "next/link";
import s from "./concepts.module.css";

export const pilotUrl = "https://mat-web-production.up.railway.app";
export const concepts = [
  { id: "editorial", label: "01 Editorial" },
  { id: "immersive", label: "02 Make room" },
  { id: "tomorrow", label: "03 Dear tomorrow" },
];
export function Arrow() {
  return <span aria-hidden="true">↗</span>;
}
export function Switcher({ current }: { current: string }) {
  return <nav className={s.switcher} aria-label="디자인 초안 선택">
    <span>DESIGN PREVIEW</span>
    {concepts.map(({ id, label }) => <Link key={id} href={`/concepts/${id}`} aria-current={current === id ? "page" : undefined}>{label}</Link>)}
  </nav>;
}
export function Photo({ className, priority = false, alt = "나무가 우거진 정원에 놓인 목재 벤치 콘셉트 이미지" }: { className?: string; priority?: boolean; alt?: string }) {
  return <div className={`${s.photo} ${className ?? ""}`}><Image src="/concepts/garden-bench.webp" alt={alt} fill sizes="(max-width: 700px) 100vw, 70vw" priority={priority} /></div>;
}
export function Footer({ current }: { current: string }) {
  return <footer className={s.footer}>
    <div className={s.footerTop}><a href="#top" className={s.footerBrand}>BenchMark<span>마음이 머무는 자리.</span></a><a href={pilotUrl}>쉼, 펴 프로젝트 방문 <Arrow /></a></div>
    <Switcher current={current} />
    <div className={s.fineprint}><span>© {new Date().getFullYear()} BenchMark</span><span>디자인 검토용 초안 · 사진은 AI 콘셉트이며 실제 현장 기록이 아닙니다.</span></div>
  </footer>;
}
