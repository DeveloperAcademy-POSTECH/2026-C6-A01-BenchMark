import Link from "next/link";
export default function NotFound() { return <div className="page-message"><h1>아직 펼쳐지지 않은 이야기예요.</h1><p>주소를 확인하거나 다른 자리의 이야기를 만나보세요.</p><Link className="button primary" href="/stories">모든 이야기 보기</Link></div>; }
