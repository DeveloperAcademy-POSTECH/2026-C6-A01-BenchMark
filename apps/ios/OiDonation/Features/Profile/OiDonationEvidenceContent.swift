//
//  OiDonationEvidenceContent.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/5/26.
//

import SwiftUI

struct OiDonationEvidenceContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let evidence: [OiEvidence]
    var attachmentName: String?
    var attachmentImage: UIImage?
    var isProcessing = false
    var canSubmit = false
    var selectedID: UUID?
    var review: OiDonationEvidenceReview?
    var message: String?
    var onAttach: () -> Void = {}
    var onSubmit: () -> Void = {}
    var onSelect: (OiEvidence) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 50) {
                VStack(spacing: 12) {
                    Button(action: onAttach) {
                        VStack(spacing: 10) {
                            if let attachmentImage {
                                Image(uiImage: attachmentImage).resizable().scaledToFit().frame(maxHeight: 100)
                                    .accessibilityHidden(true)
                            }
                            Text(attachmentName ?? "+ 파일 첨부 하기")
                                .font(CampusStyle.semibold(24)).tracking(0.48)
                                .foregroundStyle(Color(white: 93 / 255))
                                .lineLimit(2)
                            Text(attachmentName == nil ? "이미지 또는 PDF 파일만 가능" : "선택한 파일 · 10MB 이하")
                                .font(CampusStyle.medium(14)).tracking(0.28)
                                .foregroundStyle(Color(white: 161 / 255))
                        }
                        .multilineTextAlignment(.center).padding(24)
                        .frame(maxWidth: .infinity, minHeight: 180)
                        .background {
                            RoundedRectangle(cornerRadius: 30).fill(Color(white: 243 / 255)
                                .shadow(.inner(color: Color(white: 121 / 255).opacity(0.6), radius: 10)))
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 30))
                    }.buttonStyle(.plain).disabled(isProcessing)
                        .accessibilityIdentifier("donation.evidence.attach")
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        actionButton("파일 재첨부하기", enabled: attachmentName != nil && !isProcessing,
                            background: Color(red: 211 / 255, green: 219 / 255, blue: 196 / 255),
                            foreground: Color(red: 112 / 255, green: 140 / 255, blue: 64 / 255), action: onAttach)
                        actionButton("자료 검토 요청", enabled: canSubmit && !isProcessing,
                            background: Color(red: 176 / 255, green: 200 / 255, blue: 91 / 255),
                            foreground: Color(red: 247 / 255, green: 250 / 255, blue: 239 / 255), action: onSubmit)
                            .accessibilityIdentifier("donation.evidence.submit")
                    }
                    if isProcessing { ProgressView("제출 자료 처리 중").font(CampusStyle.body(14)) }
                    if let message { Text(message).font(CampusStyle.body(14)).frame(maxWidth: .infinity, alignment: .leading) }
                }.padding(.horizontal, 5)

                VStack(spacing: 10) {
                    HStack {
                        Text("제출 자료").font(.custom("Paperlogy-7Bold", size: 24, relativeTo: .title2))
                            .tracking(0.48).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("\(evidence.filter { $0.status != "draft" }.count)건").font(CampusStyle.medium(20))
                            .foregroundStyle(Color(white: 62 / 255)).padding(.horizontal, 16)
                    }
                    if evidence.isEmpty {
                        Text("아직 제출한 기부 자료가 없어요")
                            .font(CampusStyle.body(16)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 72)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(evidence) { item in
                            Button { onSelect(item) } label: { evidenceRow(item) }
                                .buttonStyle(.plain).disabled(isProcessing)
                                .accessibilityIdentifier("donation.evidence.row.\(item.id)")
                            Rectangle().fill(Color(white: 0.94)).frame(height: 0.6).accessibilityHidden(true)
                        }
                    }
                }
                if let review { OiDonationEvidenceResult(review: review) }
                Text("기부 자료 제출은 선택이에요. 운영팀은 제출 자료의 검토 결과를 안내해요. AI 검사는 참고 결과예요. 공식 납입 확인과 영수증 발급은 수납처에 문의해 주세요.")
                    .font(CampusStyle.body(13)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 50).padding(.bottom, 30)
        }
        .background(Color.white).foregroundStyle(.black)
    }

    private func actionButton(_ title: String, enabled: Bool, background: Color, foreground: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(CampusStyle.medium(16)).tracking(0.32)
                .foregroundStyle(enabled ? foreground : Color(red: 211 / 255, green: 219 / 255, blue: 196 / 255))
                .padding(.horizontal, 10).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(enabled ? background : Color(red: 241 / 255, green: 244 / 255, blue: 236 / 255), in: Capsule())
        }.buttonStyle(DonationEvidenceButtonStyle()).disabled(!enabled)
    }

    private func evidenceRow(_ item: OiEvidence) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 8))
        return VStack(alignment: .leading, spacing: 10) {
            layout {
                Text(Self.dateLabel(item.submittedAt ?? item.createdAt))
                    .font(CampusStyle.body(16)).tracking(0.32).frame(maxWidth: .infinity, alignment: .leading)
                statusBadge(item.status)
            }
            if item.id == selectedID {
                if let note = item.reviewNote, !note.isEmpty {
                    Text(note).font(CampusStyle.body(14)).fixedSize(horizontal: false, vertical: true)
                }
                if ["changes_requested", "rejected"].contains(item.status) {
                    Text("보완할 파일을 첨부한 뒤 인증 요청을 눌러 주세요.").font(CampusStyle.body(14))
                }
            }
        }
        .padding(.vertical, 20).frame(minHeight: 72).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("검토 안내와 가능한 작업을 확인합니다")
    }

    private func statusBadge(_ status: String) -> some View {
        Text(Self.statusTitle(status)).font(CampusStyle.body(16)).tracking(0.32)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(status == "pending" ? Color(red: 231 / 255, green: 238 / 255, blue: 204 / 255)
                : ["changes_requested", "rejected", "revoked"].contains(status)
                ? Color(red: 1, green: 198 / 255, blue: 151 / 255) : Color(white: 234 / 255), in: Capsule())
    }

    static func statusTitle(_ status: String) -> String {
        switch status {
        case "draft": "접수 준비"
        case "pending": "검토중"
        case "approved": "검토 완료"
        case "changes_requested": "보완 요청"
        case "rejected": "미충족"
        case "revoked": "검토 결과 철회"
        default: "상태 확인 필요"
        }
    }

    static func dateLabel(_ value: String?) -> String {
        guard let value else { return "접수일 확인 중" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return "접수일 확인 중" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE HH:mm"
        return formatter.string(from: date)
    }
}

struct OiDonationEvidenceResult: View {
    let review: OiDonationEvidenceReview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("기부 증빙 검사 결과").font(CampusStyle.semibold(20)).accessibilityAddTraits(.isHeader)
            if let summary = review.summary {
                summaryContent(summary)
            } else {
                Text("시각적 참고 검사").font(CampusStyle.medium(18))
                Text("이전 검사 결과에는 발신번호·기부 완료·중복 여부를 종합한 증빙 판정이 없어요.")
                    .foregroundStyle(.secondary)
            }
            Text("자료의 시각적 상태").font(CampusStyle.semibold(16))
            Text(review.assessment.title)
            ForEach(Array(review.assessment.findings.enumerated()), id: \.offset) { _, finding in
                Text("\(finding.location): \(finding.observation)")
            }
            ForEach(Array(review.assessment.limitations.enumerated()), id: \.offset) { _, text in Text(text) }
            Text("추가 확인 사항").font(CampusStyle.semibold(16))
            ForEach(Array(review.assessment.manualChecks.enumerated()), id: \.offset) { _, text in Text(text) }
            Text(review.notice).foregroundStyle(.secondary)
        }.font(CampusStyle.body(14)).fixedSize(horizontal: false, vertical: true)
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.96), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityIdentifier("donation.evidence.aiResult")
    }

    private func summaryContent(_ summary: OiDonationEvidenceSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.outcome.label).font(CampusStyle.semibold(24))
                .foregroundStyle(summary.sufficientEvidence ? CampusStyle.green : Color.primary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("donation.evidence.decision.\(summary.outcome.rawValue)")
            Text(summary.title).font(CampusStyle.medium(18))
            ForEach(Array(summary.reasons.enumerated()), id: \.offset) { _, reason in Text(reason) }
            if summary.sufficientEvidence {
                Text("기부 완료 근거가 충분한 문자도 검토할 수 있어요. 최종 자료 검토는 운영팀에서 진행해요.")
                    .font(CampusStyle.medium(14))
            }
            if !summary.checks.isEmpty {
                Text("판정 근거").font(CampusStyle.semibold(16))
                ForEach(Array(summary.checks.enumerated()), id: \.offset) { _, check in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.checkTitle(check.kind)).font(CampusStyle.medium(14))
                        Text(check.detail)
                    }.accessibilityElement(children: .combine)
                }
            }
            if !summary.sourceReferences.isEmpty {
                Text("대조한 출처").font(CampusStyle.semibold(16))
                ForEach(Array(summary.sourceReferences.enumerated()), id: \.offset) { _, source in
                    VStack(alignment: .leading, spacing: 4) {
                        if let url = source.safeURL {
                            Link(source.title, destination: url)
                                .frame(minHeight: 44, alignment: .leading)
                        } else {
                            Text(source.title)
                        }
                        Text("\(Self.sourceKind(source.kind)) · 확인일: \(Self.sourceDate(source.verifiedAt))").font(CampusStyle.body(12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private static func checkTitle(_ kind: String) -> String {
        switch kind {
        case "sender", "sender_phone": "실제 발신번호"
        case "completion", "payment_status": "기부 완료 내용"
        case "institution", "recipient": "기부처"
        case "duplicate", "duplicates": "중복 자료"
        case "visual", "manipulation": "수정 흔적"
        case "source", "official_source": "공식 안내 대조"
        case "case_reference", "references", "donor_reports": "기부 사례 대조"
        case "chronology", "date": "날짜와 순서"
        case "ownership": "제출자 확인"
        case "amount": "금액 표기 일관성"
        default: "확인 항목"
        }
    }

    private static func sourceDate(_ value: String) -> String {
        let date = String(value.prefix(10))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: date) == nil ? "확인 필요" : date
    }

    private static func sourceKind(_ value: String) -> String {
        switch value {
        case "official", "official_source": "공식 안내"
        case "confirmed_case", "verified_case": "확인된 사례"
        case "public_report", "donor_report", "report": "참고 후기"
        default: "참고 자료"
        }
    }
}

private struct DonationEvidenceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview("Donation verification · Reference", traits: .fixedLayout(width: 402, height: 874)) {
    OiDonationEvidenceContent(evidence: [])
}
#Preview("Donation verification · Small", traits: .fixedLayout(width: 375, height: 667)) {
    OiDonationEvidenceContent(evidence: [])
}
#Preview("Donation verification · Large", traits: .fixedLayout(width: 440, height: 956)) {
    OiDonationEvidenceContent(evidence: [])
}
