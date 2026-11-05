import SwiftUI

enum OiCreationSupplementaryScreen: String, Identifiable {
    case completion, evidence
    var id: String { rawValue }
}

/// Displays the Figma sample data for donation verification.
struct OiEvidenceDesignPreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var statusLineHeight = 12.0

    private enum Status {
        case rewarded, received, reviewing, insufficient

        var label: String {
            switch self {
            case .rewarded: "인증 완료 · 씨앗"
            case .received: "접수 완료"
            case .reviewing: "검토중"
            case .insufficient: "미충족"
            }
        }

        var fill: Color {
            switch self {
            case .rewarded: .clear
            case .received: Color(white: 234 / 255)
            case .reviewing: Color(red: 231 / 255, green: 238 / 255, blue: 204 / 255)
            case .insufficient: Color(red: 255 / 255, green: 198 / 255, blue: 151 / 255)
            }
        }
    }

    private let records: [(date: String, status: Status)] = [
        ("2026년 10월 26일 월요일 19:56", .rewarded),
        ("2026년 11월 1일 일요일 22:08", .received),
        ("2026년 10월 27일 화요일 15:27", .reviewing),
        ("2026년 10월 24일 토요일 03:41", .insufficient)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.top, 4)
            ScrollView {
                VStack(spacing: 50) {
                    attachmentSection.padding(.horizontal, 5)
                    progressSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 50)
                .padding(.bottom, 24)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .foregroundStyle(.black)
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("oi.creation.evidencePreview")
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 50, height: 50)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("뒤로")
            .accessibilityIdentifier("oi.evidencePreview.back")
            Spacer()
            HStack(spacing: 10) {
                OiStorySeedIcon()
                HStack(spacing: 3) {
                    Text("3")
                    Text("개")
                }
                .font(.custom("Paperlogy-7Bold", size: 20, relativeTo: .title3))
                .tracking(0.4)
                .frame(minHeight: 30)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(red: 1, green: 254 / 255, blue: 228 / 255), in: Capsule())
            .overlay { Capsule().strokeBorder(Color(red: 198 / 255, green: 191 / 255, blue: 91 / 255), lineWidth: 1.5) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("예시 씨앗 3개")
        }
        .padding(.horizontal, 20)
    }

    private var attachmentSection: some View {
        let actionLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return VStack(spacing: 12) {
            VStack(spacing: 10) {
                Text("+ 파일 첨부 하기")
                    .font(.custom("Paperlogy-6SemiBold", size: 24, relativeTo: .title2))
                    .tracking(0.48)
                    .foregroundStyle(Color(white: 93 / 255))
                    .frame(minHeight: 25)
                Text("PNG, JPEG, PDF 파일만 가능")
                    .font(.custom("Paperlogy-5Medium", size: 14, relativeTo: .caption))
                    .tracking(0.28)
                    .foregroundStyle(Color(white: 161 / 255))
                    .frame(minHeight: 25)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, minHeight: 180)
            .background {
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color(white: 243 / 255).shadow(.inner(color: Color(white: 121 / 255).opacity(0.6), radius: 5)))
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("디자인 미리보기에서는 파일을 첨부할 수 없어요")

            actionLayout {
                previewAction("파일 재첨부하기")
                previewAction("인증 요청")
            }
            .disabled(true)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("인증 진척도")
                    .font(.custom("Paperlogy-7Bold", size: 24, relativeTo: .title2))
                    .tracking(0.48)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("3건")
                    .font(.custom("Paperlogy-5Medium", size: 20, relativeTo: .title3))
                    .tracking(0.4)
                    .foregroundStyle(Color(white: 62 / 255))
                    .frame(minWidth: 68)
            }
            .frame(minHeight: 30)
            .accessibilityElement(children: .combine)
            .accessibilityHint("표시된 인증 내역은 예시입니다")

            VStack(spacing: 0) {
                ForEach(records, id: \.date) { record in
                    progressRow(date: record.date, status: record.status)
                    Image("OiEvidenceDivider").resizable()
                        .frame(height: 0.6)
                        .padding(.top, 0.5)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func progressRow(date: String, status: Status) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Text(date)
                .font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .body))
                .tracking(0.32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            statusBadge(status)
        }
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
        .frame(minHeight: status == .rewarded ? 65 : 72)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func statusBadge(_ status: Status) -> some View {
        if status == .rewarded {
            OiStorySeedIcon()
                .frame(width: 64, height: 38)
                .background {
                    Image("OiEvidenceReward").resizable().scaledToFill()
                        .frame(width: 64, height: 38)
                        .clipShape(Capsule())
                        .shadow(color: Color(red: 246 / 255, green: 217 / 255, blue: 35 / 255), radius: 5)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(status.label)
        } else {
            Text(status.label)
                .font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .body))
                .tracking(0.32)
                .frame(height: statusLineHeight)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(status.fill, in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func previewAction(_ title: String) -> some View {
        Button {} label: {
            Text(title)
                .font(.custom("Paperlogy-5Medium", size: 16, relativeTo: .body))
                .tracking(0.32)
                .foregroundStyle(Color("OiBorder"))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(Color("OiSoft"), in: Capsule())
        }
        .buttonStyle(OiCreationPressStyle())
    }
}
