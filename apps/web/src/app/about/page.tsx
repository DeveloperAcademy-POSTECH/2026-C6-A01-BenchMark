/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
import { Donation } from "@/components/donation";
export const dynamic = "force-dynamic";
export const metadata = { title: "프로젝트 소개" };

export default function About() {
  return <><section className="about-intro"><span className="eyebrow">쉼을 나누고, 이야기를 펴다</span><h1><img className="brand-title" src="/brand/title.svg" alt="쉼, 펴 — 기부돗자리 대여 프로젝트" /></h1><h2>하나의 돗자리,<br />하나의 이야기.</h2><p>친구들과 함께한 아카데미의 추억,<br />요즘 기억하고 싶은 순간,<br />누군가에게 전하고 싶은 한마디까지.</p><p>포카전에서 누군가 이 돗자리를 펼쳤을 때,<br />당신이 남긴 사진과 이야기도 함께 만나게 돼요.</p></section><section className="about-steps"><h2>우리의 이야기는 이렇게 이어져요.</h2><ol><li><span>01</span><h3>나의 이야기를 남겨요</h3><p>네이버 폼에서 사진 한 장과<br />100자 이내의 이야기를 보내주세요.</p></li><li><span>02</span><h3>포카전에서 함께 펼쳐요</h3><p>기부로 마련한 돗자리의 QR을 통해<br />사진과 이야기를 만나요.</p></li><li><span>03</span><h3>다음 사람의 쉼이 돼요</h3><p>행사 후 돗자리는 아카데미에 기부되어<br />날씨 좋은 날 우리의 소풍과 함께해요.</p></li></ol></section><section style={{textAlign:"center",padding:"24px"}}><Link className="button primary" href="/camera">캐릭터와 사진 찍기</Link></section><Donation detailed /></>;
}
