import { z } from "zod";

export const byteLength = (value: string) => new TextEncoder().encode(value).length;
export const storyText = z.string().trim().min(1, "이야기를 입력해주세요.").refine((s) => byteLength(s) <= 500, "이야기는 500바이트 이내로 입력해주세요.");
export const storyTitle = z.string().trim().max(80, "제목은 80자 이내로 입력해주세요.");
export const reactionKinds = ["like", "empathy", "sad", "cheer"] as const;
export type ReactionKind = typeof reactionKinds[number];
export const reactionLabels = { like: "좋아요", empathy: "공감해요", sad: "슬퍼요", cheer: "응원해요" };
export type ReactionCounts = Record<ReactionKind, number>;
export const emptyCounts = (): ReactionCounts => ({ like: 0, empathy: 0, sad: 0, cheer: 0 });

export const storyInput = z.object({
  matNumber: z.coerce.number().int().min(1).max(10000),
  matSize: z.enum(["small", "large"]),
  displayName: z.string().trim().min(1, "공개 이름을 입력해주세요.").max(40),
  title: storyTitle.default(""),
  story: storyText,
  reservationId: z.string().uuid().optional(),
  paymentVerified: z.boolean(),
  published: z.boolean(),
  revision: z.coerce.number().int().min(1).optional(),
}).refine((s) => !s.published || s.paymentVerified, "입금 확인 후 공개할 수 있습니다.");
export const uuid = z.string().uuid();
export const sizes = { small: { label: "2~3인용", price: 3000 }, large: { label: "4~5인용", price: 5000 } };
export type Story = {
  id: string; mat_number: number; mat_size: "small" | "large";
  display_name: string; title: string; story: string; reaction_count: number;
  revision: number; payment_verified?: boolean; published?: boolean;
};
