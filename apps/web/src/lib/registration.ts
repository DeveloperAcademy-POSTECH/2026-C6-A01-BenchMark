import { z } from "zod";

export const formVersion = 1;
// Add approved fields here and to the schema below; historical responses keep their version.
export const registrationFields = [
  { key: "name", label: "이름", type: "text", autoComplete: "name", placeholder: "이름을 입력해주세요", maxLength: 50 },
  { key: "phone", label: "휴대폰 번호", type: "tel", autoComplete: "tel", placeholder: "010-0000-1234", maxLength: 20 },
] as const;

export const registrationSchema = z.object({
  name: z.string().trim().min(1, "이름을 입력해주세요.").max(50, "이름은 50자 이내로 입력해주세요.")
    .refine((value) => !/[\u0000-\u001f\u007f]/u.test(value), "이름에 사용할 수 없는 문자가 있어요."),
  phone: z.string().max(20).regex(/^[0-9+()\s-]+$/, "휴대폰 번호를 확인해주세요.")
    .transform((value) => value.replace(/[()\s-]/g, "").replace(/^\+82(?:0)?/, "0"))
    .pipe(z.string().regex(/^010\d{8}$/, "010으로 시작하는 휴대폰 번호 11자리를 입력해주세요.")),
  consent: z.literal(true, { error: "개인정보 수집·이용에 동의해주세요." }),
  formVersion: z.literal(formVersion, { error: "신청서가 변경됐어요. 새로고침 후 다시 시도해주세요." }),
}).strict();

export type Registration = z.infer<typeof registrationSchema>;
export type FieldErrors = Partial<Record<"name" | "phone" | "consent" | "formVersion", string>>;

export function fieldErrors(error: z.ZodError): FieldErrors {
  return Object.fromEntries(error.issues.map((issue) => [issue.path[0], issue.message]));
}
