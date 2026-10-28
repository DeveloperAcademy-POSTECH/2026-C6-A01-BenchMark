import Link from "next/link";
import { redirect } from "next/navigation";
import { currentAccount } from "@/lib/auth/server";
import { appOrigin, authConfig, loginDestination } from "@/lib/web-config";
import { LoginSubmit } from "@/components/login-submit";
import { login, logout } from "./actions";
export const metadata = { title: "로그인" };
const errors: Record<string, string> = {
  config: "로그인 연결을 준비 중이에요. 잠시 후 다시 방문해주세요.",
  provider: "Google 로그인에 연결하지 못했어요. 다시 시도해주세요.",
  callback: "로그인이 취소되었거나 연결이 만료되었어요. 다시 시도해주세요.",
  logout: "로그아웃하지 못했어요. 다시 시도해주세요.",
};
export default async function Login({ searchParams }: { searchParams: Promise<{ next?: string; error?: string }> }) {
  const params = await searchParams;
  const next = loginDestination(params.next);
  const { user, unavailable } = await currentAccount();
  if (user && params.error !== "logout") redirect(next);
  return <section className="oi-auth oi-shell"><span className="oi-kicker">오래 남는 이야기의 시작</span><h1>반가워요,<br />오이기부입니다.</h1><p>앱에서 사용하는 Google 계정으로<br />웹에서도 함께할 수 있어요.</p>
    {params.error && <p role="alert" className="error-message">{errors[params.error] || errors.callback}</p>}
    {unavailable && authConfig() && <p role="status">계정 정보를 확인하지 못했어요. 잠시 후 다시 시도해주세요.</p>}
    {user ? <form action={logout}><button className="button primary">로그아웃 다시 시도</button></form> : authConfig() && appOrigin() ? <form action={login}><input type="hidden" name="next" value={next} /><LoginSubmit /></form> : <p className="oi-notice" role="status">로그인 연결을 준비 중이에요. 기부 안내와 공개 이야기는 지금도 볼 수 있어요.</p>}
    <Link className="text-link" href="/donate">기부 안내 먼저 보기 →</Link><p className="oi-caption">기부금 납입과 영수증은 POSTECH 공식 절차에서 진행합니다.</p></section>;
}
