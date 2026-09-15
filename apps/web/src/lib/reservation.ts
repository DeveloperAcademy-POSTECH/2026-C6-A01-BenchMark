import { z } from "zod";
import { storyText, storyTitle } from "./story";

export const reasons = {
  story: "기부자 스토리를 보고 흥미가 생겨서",
  rest: "기부로 타인에게 휴식을 제공할 수 있는 취지가 좋아서",
  project: "프로젝트가 재밌어 보이고 신기해서",
  donate: "기부를 해보고 싶어서",
  other: "기타",
} as const;
export const paymentMethods = { deposit: "무통장입금", easy: "간편결제", transfer: "계좌이체", other: "기타" } as const;
export const RESERVATION_MIN_AMOUNT = 10000;
export const RESERVATION_MAX_AMOUNT = 2147483647;
function normalizeAnonymous(input: unknown) {
  if (input && typeof input === "object" && "isAnonymous" in input && input.isAnonymous === "true") {
    return { ...input, displayName: "익명" };
  }
  return input;
}
const reservationDetails = z.object({
  isAnonymous: z.enum(["true", "false"]).default("false"),
  displayName: z.string().trim().min(1, "성함을 입력해주세요.").max(40),
  email: z.string().trim().email("이메일 주소를 확인해주세요.").max(254, "이메일은 254자 이내로 입력해주세요."),
  title: storyTitle.refine((s) => s.length > 0, "마음을 담은 한 줄을 입력해주세요."),
  story: storyText,
  paymentMethod: z.enum(["deposit", "easy", "transfer", "other"], { error: "희망 결제방법을 선택해주세요." }),
  amount: z.coerce.number().int("기부금액은 원 단위의 정수로 입력해주세요.").min(RESERVATION_MIN_AMOUNT, "기부금액은 10,000원 이상 입력해주세요.").max(RESERVATION_MAX_AMOUNT, "입력 가능한 기부금액을 초과했어요."),
  sourceStoryId: z.string().uuid().optional(),
});
export const reservationDetailsInput = z.preprocess(normalizeAnonymous, reservationDetails);
export const reservationInput = z.preprocess(normalizeAnonymous, reservationDetails.extend({
  id: z.string().uuid(),
  reason: z.enum(["story", "rest", "project", "donate", "other"], { error: "예약 이유를 선택해주세요." }),
  reasonOther: z.string().trim().max(300).default(""),
}).refine((s) => s.reason !== "other" || !!s.reasonOther, { message: "기타 이유를 입력해주세요.", path: ["reasonOther"] }));
export type Reservation = {
  id: string; display_name: string; phone: string | null; email: string | null; reason: keyof typeof reasons; reason_other: string;
  title: string; story: string; payment_method: keyof typeof paymentMethods; amount: number;
  source_story_id: string | null; story_id: string | null; created_at: string;
};
