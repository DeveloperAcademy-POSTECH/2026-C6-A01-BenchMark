import Link from "next/link";
import { officialDonationUrl } from "@/lib/web-config";
export const metadata = { title: "기부 안내" };
export default function Donate() {
  const url = officialDonationUrl();
  return <div className="oi-donate oi-shell"><Link className="back-link" href="/">← 홈으로</Link><section className="oi-donate-heading"><span className="oi-kicker">POSTECH 공식 기부</span><h1>기부를 원하시면<br />공식 절차를 확인해 주세요.</h1><p>기부는 선택입니다.<br />오이기부의 이야기 작성, 오이 배치, 카드 수집에는 기부가 필요하지 않습니다.</p></section><div className="oi-donate-grid"><section className="oi-donate-guide"><h2>기부 안내</h2><ol><li><h3>공식 절차로 기부하기</h3><p>약정·납입·영수증 발급·취소 및 환불은 학교에서 진행합니다. 오이기부는 기부금이나 결제 정보를 받지 않습니다.</p></li><li><h3>공식 납입 확인</h3><p>오이기부는 기부 증빙을 접수하지 않습니다. 납입 확인과 영수증은 공식 수납처에 문의해 주세요.</p></li></ol></section><aside className="oi-donate-card"><span className="oi-kicker">POSTECH 공식 기부</span><h2>학교 기부 안내</h2><p>학교의 공식 기부 페이지에서<br />절차를 확인해 주세요.</p>{url ? <a className="button primary" href={url} target="_blank" rel="noopener noreferrer">공식 기부 페이지로 이동 ↗<span className="sr-only"> (새 창)</span></a> : <div className="oi-notice" role="status"><strong>공식 기부 연결 준비 중</strong><p>공식 연결 주소가 준비되면 여기서 안내하겠습니다.</p></div>}<p className="oi-caption">페이지를 여는 것만으로 기부가 접수되지는 않습니다.</p></aside></div></div>;
}
