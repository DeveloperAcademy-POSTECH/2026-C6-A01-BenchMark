import {test,expect} from "@playwright/test";
import {Pool} from "pg";
import {randomUUID} from "node:crypto";
test("admin reviews campus stories while anonymous users only receive published data",async({page,request})=>{
 if(!process.env.DATABASE_URL?.endsWith("/benchmark_mat_test"))throw new Error("Use isolated test DB");
 const pool=new Pool({connectionString:process.env.DATABASE_URL});let writerID="";const oiID=randomUUID();
 const errors:string[]=[];page.on("pageerror",e=>errors.push(e.message));
 try {
  await page.goto("/admin/campus");await page.getByLabel("비밀번호",{exact:true}).fill(process.env.ADMIN_PASSWORD!);
  await page.getByRole("button",{name:"관리자 페이지로 이동"}).click();
  await expect(page.getByRole("heading",{name:"캠퍼스 오이 관리",exact:true})).toBeVisible();
  await expect(page.getByRole("button",{name:"작성 코드 발급",exact:true})).toBeDisabled();
  await page.getByLabel("외부에서 증빙을 확인했고 이 이용자의 글 작성을 승인합니다.").check();
  const issued=page.waitForResponse(r=>r.url().endsWith("/api/admin/campus/grants")&&r.request().method()==="POST");
  await page.getByRole("button",{name:"작성 코드 발급",exact:true}).click();
  const grant=await (await issued).json();writerID=grant.id;
  const auth=await (await request.post("/api/campus/session",{data:{code:grant.code}})).json();
  const latitude=36.008,longitude=129.3235; // Campus outdoor test fixture, not donor data.
  const created=await request.post("/api/campus/ois",{headers:{authorization:`Bearer ${auth.token}`},data:{id:oiID,campusID:"postech",model:"helmet-oi",latitude,longitude,heightMeters:1,headingDegrees:10,displayName:"가상 테스트",title:"공개 전 검토 이야기",story:"운영 데이터와 무관한 검증 글입니다."}});expect(created.status()).toBe(201);
  await page.getByRole("button",{name:"코드 숨기기",exact:true}).click();
  await page.getByRole("button",{name:"새로고침",exact:true}).click();
  await expect(page.getByRole("heading",{name:"공개 전 검토 이야기 · 공개 검토 대기"})).toBeVisible();
  expect((await request.get(`/api/campus/ois/${oiID}`)).status()).toBe(404);
  await page.getByRole("button",{name:"검토 완료 · 공개",exact:true}).click();
  await expect(page.getByRole("heading",{name:"공개 전 검토 이야기 · 공개 중"})).toBeVisible();
  expect((await request.get(`/api/campus/ois/${oiID}`)).status()).toBe(200);
  await page.getByRole("button",{name:"비공개",exact:true}).click();
  await expect(page.getByRole("heading",{name:"공개 전 검토 이야기 · 비공개"})).toBeVisible();
  expect((await request.get(`/api/campus/ois/${oiID}`)).status()).toBe(404);
  for(const width of [390,1440]){await page.setViewportSize({width,height:900});expect(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);}
  await expect(page.locator("header.site-header")).toHaveCount(1);
  await page.screenshot({path:test.info().outputPath("campus-admin.png"),fullPage:true});
  expect(errors).toEqual([]);
 } finally {
  await pool.query("DELETE FROM campus_reviews WHERE oi_id=$1",[oiID]);await pool.query("DELETE FROM campus_ois WHERE id=$1",[oiID]);
  if(writerID)await pool.query("DELETE FROM campus_writers WHERE id=$1",[writerID]);await pool.end();
 }
});
