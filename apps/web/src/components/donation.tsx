/* eslint-disable @next/next/no-img-element */
import Link from "next/link";

export function Donation({ detailed = false }: { detailed?: boolean }) {
  return <section className="donation" aria-labelledby="donation-title"><div className="donation-heading"><span className="eyebrow">다음 이야기는, 당신의 이야기</span><h2 id="donation-title">당신의 이야기도<br />한 자리 펼쳐볼까요?</h2><p>사진 한 장, 100자 안의 작은 이야기.<br />여러분의 기부가 누군가의 쉼이 됩니다.</p></div>
    <div className="donation-details"><div className="mat-options"><div><img src="/brand/small-mat.png" alt="2~3인용" width="117" height="40" /><strong>3,000원</strong></div><div><img src="/brand/large-mat.png" alt="4~5인용" width="117" height="40" /><strong>5,000원</strong></div></div>
      <p className="donation-note">기부 한 건이 돗자리 한 개로 이어집니다.</p>
      {detailed && <div className="bank-info"><h3>입금 안내</h3><p>{process.env.DONATION_BANK || "신한은행"} · {process.env.DONATION_ACCOUNT || "111-111-111111"}<br />예금주 {process.env.DONATION_ACCOUNT_HOLDER || "이돈혁"}</p>{process.env.DONATION_ACCOUNT_CONFIRMED !== "true" && <p className="notice">현재 계좌는 임시 표시입니다. 실제 입금은 신청 폼의 운영진 안내를 확인해주세요.</p>}</div>}
      <a className="button primary" href="https://naver.me/Gjyqyq7s" target="_blank" rel="noopener noreferrer">내 이야기 남기러 가기 <span aria-hidden="true">↗</span><span className="sr-only"> (네이버 폼, 새 창)</span></a>
      {!detailed && <Link className="text-link" href="/about#donation-title">기부 방법 알아보기</Link>}
    </div></section>;
}
