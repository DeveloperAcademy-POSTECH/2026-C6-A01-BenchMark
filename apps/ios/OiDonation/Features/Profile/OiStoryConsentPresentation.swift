import Foundation

struct OiStoryConsentClause: Identifiable, Equatable, Sendable {
    enum ID: String, CaseIterable, Identifiable, Sendable {
        case storyWriting
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
        agreedClauseIDs.count == OiStoryConsentClause.ID.allCases.count
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
    static let figmaDrafts: [Self] = [
        Self(
            id: .storyWriting,
            title: "[필수] 이야기 내용 작성 시 규정 동의",
            paragraphs: [
                Paragraph(id: "fact", heading: "1. 사실에 기반해 작성해 주세요.", body: "기부 내역과 이야기는 실제 경험을 바탕으로 작성해 주세요. 허위 내용이나 다른 사람의 기부 내역을 도용한 경우 게시물 삭제 또는 서비스 이용이 제한될 수 있습니다."),
                Paragraph(id: "respect", heading: "2. 서로를 존중하는 내용을 작성해주세요.", body: "욕설, 비방, 혐오·차별 표현, 음란물, 광고·스팸 등 서비스 취지에 맞지 않는 내용은 수정 요청 또는 삭제 대상이 될 수 있습니다."),
                Paragraph(id: "privacy", heading: "3. 개인정보가 노출되지 않도록 주의해 주세요.", body: "본인이나 다른 사람의 연락처, 주소, 주민등록번호, 계좌번호 등은 게시하지 말아 주세요. 특히 기부 대상자의 사생활이나 민감한 사연이 동의 없이 공개되지 않도록 주의해 주세요."),
                Paragraph(id: "rights", heading: "4. 사진과 글의 사용 권한을 확인해 주세요.", body: "직접 작성하거나 사용 허락을 받은 글·사진을 등록해주세요. 다른 사람이 식별되는 사진이나 사연을 게시할 때는 당사자의 동의를 확인해 주세요.")
            ],
            agreementText: "위 안내를 확인했으며, 이야기 작성 규정에 동의합니다"
        ),
        Self(
            id: .donationVerification,
            title: "[필수] 기부 인증 규정",
            paragraphs: [
                Paragraph(id: "evidence", heading: "1. 기부 인증 자료를 명확하게 제출해 주세요.", body: "기부처, 기부일, 금액 등 인증에 필요한 정보가 확인되어야 합니다. 자료가 불명확하거나 작성한 내용과 다른 경우 추가 자료 제출 또는 재인증을 요청할 수 있으며, 확인이 완료될 때까지 인증이 보류될 수 있습니다. 인증에 불필요한 개인정보는 가려 주세요."),
                Paragraph(id: "documents", heading: "2. 제출 가능한 인증 자료", body: "■ 선택 항목\n기부인증서, 기부금영수증, 기부확인문자, 기부확인서, 기부입금내역")
            ],
            agreementText: "위 안내를 확인했으며, 기부 인증 규정에 동의합니다"
        ),
        Self(
            id: .moderation,
            title: "[필수] 운영정책 위반 시 게시물 조치 규정",
            paragraphs: [
                Paragraph(id: "moderation", heading: "1. 개인정보 수집 및 이용 목적", body: "위 안내를 위반하거나 개인정보 노출 등으로 피해가 우려되는 게시물을 운영진이 노출을 제한하거나 삭제할 수 있습니다. 필요한 경우 수정 또는 재인증을 요청할 수 있으며, 조치에 대한 문의는 고객센터를 통해 접수할 수 있습니다.")
            ],
            agreementText: "위 안내를 확인했으며, 조치 규정에 동의합니다"
        )
    ]
}
