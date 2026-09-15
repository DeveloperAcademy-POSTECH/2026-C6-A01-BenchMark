/* eslint-disable @next/next/no-img-element */
import Link from "next/link";
export function Donation({ sourceStoryId, compact = false, buttonLabel = "나도 이야기 남기기" }: { sourceStoryId?: string; compact?: boolean; buttonLabel?: string }) {
  return <section className={`donation ${compact || sourceStoryId ? "story-donation" : ""}`} aria-labelledby="donation-title"><div className="donation-heading"><span className="eyebrow">다음 이야기는, 당신의 이야기</span><h2 id="donation-title">당신의 이야기도<br />한 자리 펼쳐볼까요?</h2><p>사진 한 장과 작은 이야기.<br />여러분의 마음이 누군가의 쉼이 됩니다.</p></div><div className="donation-details"><div className="mat-options"><img src="/brand/small-mat.png" alt="2~3인용 돗자리" width="117" height="40" /><img src="/brand/large-mat.png" alt="4~5인용 돗자리" width="117" height="40" /></div><p className="donation-note">원하는 금액으로 기부를 예약해주세요.<br />지금은 결제 없이 예약만 받아요.</p><Link className="button primary" href={sourceStoryId ? `/reserve?from=${sourceStoryId}` : "/reserve"}>{buttonLabel} →</Link></div></section>;
}
