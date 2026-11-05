import SwiftUI

enum OiCreationSupplementaryScreen: String, Identifiable {
    case completion, evidence
    var id: String { rawValue }
}

/// Design inspection only: never opens files, uploads evidence, grants seeds or approves writing.
struct OiEvidenceDesignPreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Label("디자인 미리보기", systemImage: "eye").font(.headline)
                Text("실제 증빙 제출은 아직 열지 않았어요. 아래 내역은 화면을 확인하기 위한 예시입니다.")
                    .font(.subheadline).foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    VStack(spacing: 10) {
                        Text("+ 파일 첨부 하기").font(CampusStyle.medium(20))
                        Text("PNG, JPEG, PDF, HWP 파일만 가능").font(CampusStyle.body(12))
                        Text("미리보기에서는 파일을 선택하지 않아요").font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(Color("OiLight"), in: RoundedRectangle(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).stroke(Color("OiBorder"), lineWidth: 2) }
                    HStack(spacing: 8) {
                        previewAction("파일 재첨부하기")
                        previewAction("인증 요청")
                    }.disabled(true)
                }
                HStack {
                    Text("인증 진척도").font(CampusStyle.semibold(18))
                    Spacer()
                    Text("예시").font(.caption).padding(8).background(Color("OiLight"), in: Capsule())
                }
                VStack(spacing: 0) {
                    ForEach(["접수 완료", "검토 중", "미충족"], id: \.self) { status in
                        HStack {
                            Text("예시 인증 내역").font(CampusStyle.body(14))
                            Spacer()
                            Text(status).font(.caption).padding(.horizontal, 14).padding(.vertical, 10)
                                .background(Color("OiLight"), in: Capsule())
                        }.frame(minHeight: 72)
                        Divider()
                    }
                }
                Text("지원 형식과 증빙 운영 정책은 확정 전입니다. 씨앗 지급이나 작성 승인은 처리되지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .navigationTitle("기부 인증 미리보기").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("oi.creation.evidencePreview")
    }

    private func previewAction(_ title: String) -> some View {
        Button(title) {}.font(CampusStyle.body(14)).frame(maxWidth: .infinity, minHeight: 44)
            .background(Color("OiLight"), in: Capsule())
    }
}
