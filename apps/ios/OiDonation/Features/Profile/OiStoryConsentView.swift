import SwiftUI

struct OiStoryConsentView: View {
    let clauses: [OiStoryConsentClause]
    var continueTitle = "오이 커스텀 시작하기"
    var onContinue: () -> Void = {}
    var onExit: (() -> Void)?
    var showsHeader = true
    var showsContinueButton = true
    var state: Binding<OiStoryConsentState>?
    var onSelectStage: ((Int) -> Void)?
    var onSkip: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var localConsentState = OiStoryConsentState()
    private var consentState: OiStoryConsentState { state?.wrappedValue ?? localConsentState }

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader { topHeader.padding(.bottom, 20) }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if let onSkip {
                        Text("내 지도에만 배치할 때는 공개 약관 동의가 필요 없어요.")
                            .font(CampusStyle.body(14)).foregroundStyle(.secondary)
                        OiCreationNextButton(title: "나만의 오이 만들기", action: onSkip)
                            .accessibilityIdentifier("oi.consent.makePersonalOi")
                    }
                    VStack(spacing: 50) {
                        ForEach(clauses) { clause in
                            clauseSection(clause)
                        }
                    }

                    if showsContinueButton { footerActions }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
                .padding(.top, 20)
            }
            .scrollIndicators(.hidden)
            .clipped()
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var topHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .frame(width: 50, height: 50)
            .padding(.top, 4)
            .accessibilityLabel("뒤로")

            OiCreationProgressHeader(step: 1, onSelect: onSelectStage)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 65)
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
            .accessibilityIdentifier("oi.consent.details.\(clause.id.rawValue)")
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
            .accessibilityIdentifier("oi.consent.agree.\(clause.id.rawValue)")
            .accessibilityLabel(clause.agreementText)
            .accessibilityValue(consentState.isAgreed(to: clause.id) ? "동의함" : "동의하지 않음")
            .accessibilityHint("두 번 탭하여 동의 상태를 변경합니다")
        }
    }

    private var footerActions: some View {
        VStack(spacing: 10) {
            Button {
                if let onExit { onExit() } else { dismiss() }
            } label: {
                Text("나가기")
                    .font(.custom("Paperlogy-5Medium", size: 16, relativeTo: .body))
                    .tracking(0.32)
                    .underline()
                    .foregroundStyle(Color.primary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("oi.consent.exit")

            continueButton
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
        .accessibilityIdentifier("oi.creation.next")
        .accessibilityHint(
            consentState.allRequiredClausesAreAgreed
                ? "이야기 작성의 다음 단계로 이동합니다"
                : "필수 안내에 모두 동의하면 사용할 수 있습니다"
        )
    }

    private func toggleAgreement(for id: OiStoryConsentClause.ID) {
        var updated = consentState
        updated.setAgreed(!updated.isAgreed(to: id), to: id)
        if let state { state.wrappedValue = updated } else { localConsentState = updated }
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
        OiStoryConsentView(clauses: OiStoryConsentClause.writingClauses)
    }
}
