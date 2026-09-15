import { z } from "zod";
import { storyText, storyTitle } from "./story";

export const reasons = {
  story: "기부자 스토리를 보고 흥미가 생겨서",
  rest: "기부로 타인에게 휴식을 제공할 수 있는 취지가 좋아서",
  project: "프로젝트가 재밌어 보이고 신기해서",
  donate: "기부를 해보고 싶어서",
  other: "기타",
} as const;
export const paymentMethods = { deposit: "무통장입금", easy: "간편결제", transfer: "계좌이체" } as const;
export const reservationInput = z.object({
  id: z.string().uuid(),
  displayName: z.string().trim().min(1, "성함을 입력해주세요.").max(40),
  phone: z.string().transform((s) => s.replace(/[\s-]/g, "")).pipe(z.string().regex(/^01[016789]\d{7,8}$/, "휴대폰번호를 확인해주세요.")),
  reason: z.enum(["story", "rest", "project", "donate", "other"], { error: "예약 이유를 선택해주세요." }),
  reasonOther: z.string().trim().max(300).default(""),
  title: storyTitle.refine((s) => s.length > 0, "제목을 입력해주세요."),
  story: storyText,
  paymentMethod: z.enum(["deposit", "easy", "transfer"], { error: "희망 결제방법을 선택해주세요." }),
  amount: z.coerce.number().int("금액은 원 단위로 입력해주세요.").min(1, "예약 금액을 입력해주세요.").max(2147483647, "입력 가능한 금액을 초과했습니다."),
  sourceStoryId: z.string().uuid().optional(),
}).refine((s) => s.reason !== "other" || !!s.reasonOther, { message: "기타 이유를 입력해주세요.", path: ["reasonOther"] });
export type Reservation = {
  id: string; display_name: string; phone: string; reason: keyof typeof reasons; reason_other: string;
  title: string; story: string; payment_method: keyof typeof paymentMethods; amount: number;
  source_story_id: string | null; story_id: string | null; created_at: string;
};
