import Foundation

enum OiWritingGuidance {
    static let available = "로그인하면 기부 증빙 없이 오이를 꾸미고 내 지도에 바로 배치할 수 있어요."
    static let unavailable = "지금은 공개 검토 요청을 받지 않아요. 내 지도에는 오이를 배치할 수 있어요."
    static let publication = "다른 사람의 지도와 현장 AR에 공개하려면 이야기·사진·꾸민 오이의 검토를 요청해 주세요."
}

struct OiStoryConsentClause: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Identifiable, Sendable {
        case storyWriting
        // Preserve consent stored by older drafts.
        case donationVerification
        case moderation

        var id: String { rawValue }
    }

    struct Paragraph: Identifiable, Equatable, Sendable {
        let id: String
        let heading: String
        let body: String
    }

    let id: ID
    let title: String
    let paragraphs: [Paragraph]
    let agreementText: String
}

struct OiStoryConsentState: Equatable, Sendable {
    private(set) var agreedClauseIDs: Set<OiStoryConsentClause.ID> = []

    init(savedIDs: Set<String> = []) {
        agreedClauseIDs = Set(savedIDs.compactMap(OiStoryConsentClause.ID.init(rawValue:)))
    }

    var savedIDs: Set<String> { Set(agreedClauseIDs.map(\.rawValue)) }

    var allRequiredClausesAreAgreed: Bool {
        OiStoryConsentClause.writingClauses.allSatisfy { agreedClauseIDs.contains($0.id) }
    }

    func isAgreed(to id: OiStoryConsentClause.ID) -> Bool {
        agreedClauseIDs.contains(id)
    }

    mutating func setAgreed(_ agreed: Bool, to id: OiStoryConsentClause.ID) {
        if agreed {
            agreedClauseIDs.insert(id)
        } else {
            agreedClauseIDs.remove(id)
        }
    }
}

extension OiStoryConsentClause {
    static let writingClauses: [Self] = [
        Self(
            id: .storyWriting,
            title: "[필수] 이야기 내용 작성 시 규정 동의",
            paragraphs: [
                Paragraph(id: "fact", heading: "1. 사실에 기반해 작성해 주세요.", body: "이야기는 실제 경험을 바탕으로 작성해 주세요. 허위 내용을 올리거나 다른 사람의 이야기를 도용하면 게시물이 삭제되거나 서비스 이용이 제한될 수 있습니다."),
                Paragraph(id: "respect", heading: "2. 서로를 존중하는 내용을 작성해주세요.", body: "욕설, 비방, 혐오·차별 표현, 음란물, 광고·스팸 등 서비스 취지에 맞지 않는 내용은 수정 요청 또는 삭제 대상이 될 수 있습니다."),
                Paragraph(id: "privacy", heading: "3. 개인정보가 노출되지 않도록 주의해 주세요.", body: "본인이나 다른 사람의 연락처, 주소, 주민등록번호, 계좌번호 등은 게시하지 말아 주세요. 다른 사람의 사생활이나 민감한 사연을 공개하려면 당사자의 동의를 받아 주세요."),
                Paragraph(id: "rights", heading: "4. 사진과 글의 사용 권한을 확인해 주세요.", body: "직접 작성하거나 사용 허락을 받은 글·사진을 등록해주세요. 다른 사람이 식별되는 사진이나 사연을 게시할 때는 당사자의 동의를 확인해 주세요.")
            ],
            agreementText: "위 안내를 확인했으며, 이야기 작성 규정에 동의합니다"
        ),
        Self(
            id: .moderation,
            title: "[필수] 운영정책 위반 시 게시물 조치 규정",
            paragraphs: [
                Paragraph(id: "moderation", heading: "1. 게시물 검토와 조치", body: "운영팀은 이야기, 사진, 꾸민 오이와 카드를 공개 전에 검토합니다. 카드에 넣은 문구와 배경 사진도 승인 후 공개됩니다. 규정을 위반하거나 개인정보 노출 등으로 피해가 우려되는 게시물은 수정을 요청하거나 노출을 제한할 수 있습니다. 조치에 대한 문의는 고객센터로 접수해 주세요.")
            ],
            agreementText: "위 안내를 확인했으며, 조치 규정에 동의합니다"
        )
    ]
}
