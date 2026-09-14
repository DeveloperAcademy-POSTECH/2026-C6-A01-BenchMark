import { z } from "zod";

export const storyInput = z.object({
  matNumber: z.coerce.number().int().min(1).max(10000),
  matSize: z.enum(["small", "large"]),
  displayName: z.string().trim().min(1, "공개 이름을 입력해주세요.").max(40),
  story: z.string().trim().min(1, "이야기를 입력해주세요.").refine((s) => Array.from(s).length <= 100, "이야기는 100자 이내로 입력해주세요."),
  paymentVerified: z.boolean(),
  published: z.boolean(),
  revision: z.coerce.number().int().min(1).optional(),
}).refine((s) => !s.published || s.paymentVerified, "입금 확인 후 공개할 수 있습니다.");
export const uuid = z.string().uuid();
export const sizes = { small: { label: "2~3인용", price: 3000 }, large: { label: "4~5인용", price: 5000 } };
export type Story = {
  id: string; mat_number: number; mat_size: "small" | "large";
  display_name: string; story: string; reaction_count: number;
  revision: number; payment_verified?: boolean; published?: boolean;
};
