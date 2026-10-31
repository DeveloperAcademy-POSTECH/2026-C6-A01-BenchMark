import SwiftUI

struct OiStoryConsentView: View {
    let clauses: [OiStoryConsentClause]
    var onContinue: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 50) {
                ForEach(clauses) { clause in
                    clauseSection(clause)
                }

                continueButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 38)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel("뒤로")
            }

            ToolbarItem(placement: .topBarTrailing) {
                progressHeader
                    .frame(width: 298, height: 50)
                    .offset(y: 13)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private func clauseSection(_ clause: OiStoryConsentClause) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(clause.title)
                .font(.custom("Paperlogy-6SemiBold", size: 18, relativeTo: .headline))
                .lineLimit(2)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(clause.paragraphs) { paragraph in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paragraph.heading)
                                .font(.custom("Paperlogy-7Bold", size: 14, relativeTo: .subheadline))
                            Text(paragraph.body)
                                .font(.custom("Paperlogy-3Light", size: 14, relativeTo: .subheadline))
                        }
                        .tracking(0.28)
                        .lineSpacing(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .frame(height: clause.id == .moderation ? 104 : 145)
            .overlay {
                Rectangle().stroke(Color("OiBorder"), lineWidth: 1)
            }

            Button(action: {}) {
                HStack(spacing: 4) {
                    Image("ConsentUnchecked")
                        .resizable()
                        .frame(width: 18, height: 18)

                    Text(clause.agreementText)
                        .font(.custom("Paperlogy-5Medium", size: 14, relativeTo: .subheadline))
                        .tracking(0.28)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(consentTextColor)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .background(consentBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .allowsHitTesting(false)
            .accessibilityLabel(clause.agreementText)
            .accessibilityHint("동의 선택은 다음 구현 단계에서 연결됩니다")
        }
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            Text("오이 커스텀 시작하기")
                .font(.custom("Paperlogy-5Medium", size: 17, relativeTo: .body))
                .tracking(0.34)
                .foregroundStyle(consentBackgroundColor)
                .frame(maxWidth: .infinity, minHeight: 57)
                .background(Color("OiGreen"), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(false)
        .accessibilityHint("필수 안내 동의 동작은 다음 구현 단계에서 연결됩니다")
    }

    private var progressHeader: some View {
        HStack(spacing: 4) {
            progressStep(number: 1, position: .raised, active: true, label: "약관동의")
            progressStep(number: 2, position: .lowered, active: false)
            progressStep(number: 3, position: .raised, active: false)
            progressStep(number: 4, position: .lowered, active: false)
        }
        .frame(width: 298, height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("4단계 중 1단계, 약관 동의")
    }

    private enum StepPosition {
        case raised
        case lowered
    }

    private func progressStep(
        number: Int,
        position: StepPosition,
        active: Bool,
        label: String? = nil
    ) -> some View {
        ZStack(alignment: .bottom) {
            ZStack {
                Image(stepAsset(position: position, active: active))
                    .resizable()
                    .frame(
                        width: position == .raised ? 66 : 70,
                        height: position == .raised ? 39 : 30
                    )

                Text("STEP \(number)")
                    .font(.custom("Paperlogy-7Bold", size: 10, relativeTo: .caption2))
                    .foregroundStyle(active ? consentBackgroundColor : Color("OiGreen").opacity(0.5))
            }
            .frame(maxHeight: .infinity, alignment: position == .raised ? .top : .bottom)

            if let label {
                Text(label)
                    .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
                    .tracking(0.24)
                    .foregroundStyle(consentTextColor)
            }
        }
        .frame(width: 71, height: 64)
    }

    private func stepAsset(position: StepPosition, active: Bool) -> String {
        if active { return "ConsentStepActive" }
        return position == .raised ? "ConsentStepInactiveRaised" : "ConsentStepInactiveLowered"
    }

    private var consentTextColor: Color {
        Color(red: 84 / 255, green: 105 / 255, blue: 48 / 255)
    }

    private var consentBackgroundColor: Color {
        Color(red: 241 / 255, green: 244 / 255, blue: 236 / 255)
    }
}

#Preview {
    NavigationStack {
        OiStoryConsentView(clauses: OiStoryConsentClause.figmaDrafts)
    }
}
