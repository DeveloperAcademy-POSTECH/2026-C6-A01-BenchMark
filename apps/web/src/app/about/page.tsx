/* eslint-disable @next/next/no-img-element */
import { Donation } from "@/components/donation";
export const metadata = { title: "프로젝트 소개" };
export default function About() {
  return <><section className="about-intro"><span className="eyebrow">쉼을 나누고, 이야기를 펴다</span><h1><img className="brand-title" src="/brand/title.svg" alt="쉼, 펴 — 기부돗자리 대여 프로젝트" /></h1><h2>하나의 돗자리,<br />하나의 이야기.</h2><p>친구들과 함께한 아카데미의 추억,<br />요즘 기억하고 싶은 순간,<br />누군가에게 전하고 싶은 한마디까지.</p><p>포카전에서 누군가 이 돗자리를 펼쳤을 때,<br />당신이 남긴 사진과 이야기도 함께 만나게 돼요.</p></section><section className="about-steps"><h2>우리의 이야기는 이렇게 이어져요.</h2><ol><li><span>01</span><h3>나의 이야기를 남겨요</h3><p>사진 한 장과 500바이트 이내의 이야기,<br />원하는 금액으로 기부를 예약해주세요.</p></li><li><span>02</span><h3>운영진과 함께 준비해요</h3><p>운영진이 예약을 확인하고 연락드려요.<br />기부가 진행되면 검토 후 이야기를 공개해요.</p></li><li><span>03</span><h3>다음 사람의 쉼이 돼요</h3><p>기부로 마련한 돗자리는 포카전과<br />아카데미의 소풍에서 함께 펼쳐져요.</p></li></ol></section><Donation detailed /></>;
}
