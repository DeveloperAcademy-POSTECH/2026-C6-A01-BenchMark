import SwiftUI

struct OiStoryConsentView: View {
    let clauses: [OiStoryConsentClause]
    var continueTitle = "오이 커스텀 시작하기"
    var onContinue: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var consentState = OiStoryConsentState()

    var body: some View {
        VStack(spacing: 0) {
            topHeader

            Color.clear
                .frame(height: 29)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 50) {
                    ForEach(clauses) { clause in
                        clauseSection(clause)
                    }

                    continueButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .clipped()
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var topHeader: some View {
        GeometryReader { geometry in
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .frame(width: 50, height: 50)
            .offset(x: 20, y: 4)
            .accessibilityLabel("뒤로")

            progressHeader(width: max(0, geometry.size.width - 104))
                .offset(x: 84, y: 1)
        }
        .frame(height: 65)
        .background(Color(.systemBackground))
    }

    private func clauseSection(_ clause: OiStoryConsentClause) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(clause.title)
                .font(.custom("Paperlogy-6SemiBold", size: 18, relativeTo: .headline))
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

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

            Button {
                toggleAgreement(for: clause.id)
            } label: {
                HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 4) {
                    Image(consentState.isAgreed(to: clause.id) ? "ConsentChecked" : "ConsentUnchecked")
                        .resizable()
                        .frame(width: 18, height: 18)

                    Text(clause.agreementText)
                        .font(.custom("Paperlogy-5Medium", size: 14, relativeTo: .subheadline))
                        .tracking(0.28)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(consentTextColor)
                .padding(.horizontal, 12)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 10 : 0)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                .background(
                    agreementBackgroundColor(for: clause.id),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(clause.agreementText)
            .accessibilityValue(consentState.isAgreed(to: clause.id) ? "동의함" : "동의하지 않음")
            .accessibilityHint("두 번 탭하여 동의 상태를 변경합니다")
        }
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            Text(continueTitle)
                .font(.custom("Paperlogy-5Medium", size: 17, relativeTo: .body))
                .tracking(0.34)
                .foregroundStyle(continueButtonTextColor)
                .frame(maxWidth: .infinity, minHeight: 57)
                .background(continueButtonColor, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(!consentState.allRequiredClausesAreAgreed)
        .accessibilityHint(
            consentState.allRequiredClausesAreAgreed
                ? "이야기 작성의 다음 단계로 이동합니다"
                : "필수 안내 세 항목에 모두 동의하면 사용할 수 있습니다"
        )
    }

    private func toggleAgreement(for id: OiStoryConsentClause.ID) {
        consentState.setAgreed(!consentState.isAgreed(to: id), to: id)
    }

    private func progressHeader(width: CGFloat) -> some View {
        let scale = width / 298
        let raisedWidth = 71.394 * scale
        let loweredWidth = 69.446 * scale
        let spacing = 5.106 * scale

        return HStack(spacing: spacing) {
            progressStep(number: 1, position: .raised, active: true, label: "약관동의", width: raisedWidth)
            progressStep(number: 2, position: .lowered, active: false, width: loweredWidth)
            progressStep(number: 3, position: .raised, active: false, width: raisedWidth)
            progressStep(number: 4, position: .lowered, active: false, width: loweredWidth)
        }
        .frame(width: width, height: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("4단계 중 1단계, 약관 동의")
    }

    private enum StepPosition {
        case raised
        case lowered
    }

    @ViewBuilder
    private func progressStep(
        number: Int,
        position: StepPosition,
        active: Bool,
        label: String? = nil,
        width: CGFloat
    ) -> some View {
        if position == .lowered {
            loweredProgressStep(number: number, active: active, width: width)
        } else {
            raisedProgressStep(number: number, active: active, label: label, width: width)
        }
    }

    private func loweredProgressStep(number: Int, active: Bool, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image(stepAsset(position: .lowered, active: active))
                .resizable()
                .frame(width: 69.8566, height: 29.991)
                .offset(y: -3)

            Text("STEP \(number)")
                .font(.custom("Paperlogy-7Bold", size: 10, relativeTo: .caption2))
                .foregroundStyle(active ? consentBackgroundColor : Color("OiGreen").opacity(0.5))
                .frame(width: 69, height: 22)
                .offset(y: 5)
        }
        .frame(width: 69.8566, height: 29.991)
        .frame(width: width, height: 64, alignment: .bottomLeading)
    }

    private func raisedProgressStep(
        number: Int,
        active: Bool,
        label: String?,
        width: CGFloat
    ) -> some View {
        ZStack(alignment: .bottom) {
            ZStack {
                Image(stepAsset(position: .raised, active: active))
                    .resizable()
                    .frame(width: 66, height: 39)
                    .rotationEffect(.degrees(16.63))

                Text("STEP \(number)")
                    .font(.custom("Paperlogy-7Bold", size: 10, relativeTo: .caption2))
                    .foregroundStyle(active ? consentBackgroundColor : Color("OiGreen").opacity(0.5))
            }
            .frame(maxHeight: .infinity, alignment: .top)

            if let label {
                Text(label)
                    .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
                    .tracking(0.24)
                    .foregroundStyle(consentTextColor)
                    .frame(width: min(68, width), height: 25, alignment: .top)
            }
        }
        .frame(width: width, height: 64)
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

    private func agreementBackgroundColor(for id: OiStoryConsentClause.ID) -> Color {
        consentState.isAgreed(to: id) ? Color("OiBorder") : consentBackgroundColor
    }

    private var continueButtonColor: Color {
        consentState.allRequiredClausesAreAgreed
            ? Color("OiGreen")
            : Color(red: 234 / 255, green: 238 / 255, blue: 226 / 255)
    }

    private var continueButtonTextColor: Color {
        consentState.allRequiredClausesAreAgreed ? consentBackgroundColor : Color("OiGreen")
    }
}

#Preview {
    NavigationStack {
        OiStoryConsentView(clauses: OiStoryConsentClause.figmaDrafts)
    }
}
