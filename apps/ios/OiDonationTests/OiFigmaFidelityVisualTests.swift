//
//  OiFigmaFidelityVisualTests.swift
//  OiDonationTests
//
//  Created by 이돈혁 on 11/3/26.
//

import SwiftUI
import UIKit
import XCTest
@testable import OiDonation

/// Captures the production views with local test fixtures for human Figma comparison.
/// The assertions detect missing renders; they do not claim pixel-perfect fidelity.
@MainActor
final class OiFigmaFidelityVisualTests: XCTestCase {
    private struct Variant {
        let name: String
        let size: CGSize
        let dynamicTypeSize: DynamicTypeSize
    }

    private var variants: [Variant] {
        [
            Variant(name: "402x874", size: CGSize(width: 402, height: 874), dynamicTypeSize: .large),
            Variant(name: "375x667", size: CGSize(width: 375, height: 667), dynamicTypeSize: .large),
            Variant(name: "440x956", size: CGSize(width: 440, height: 956), dynamicTypeSize: .large),
            Variant(name: "accessibility5", size: CGSize(width: 402, height: 874), dynamicTypeSize: .accessibility5)
        ]
    }

    func testDonationEvidenceCaptures() async throws {
        let fixture = try isolatedDefaults()
        let previous = OiStoreURLProtocol.handle
        let backend = OiTestBackend()
        backend.install()
        let fallback = OiStoreURLProtocol.handle
        let statuses = ["approved", "pending", "changes_requested", "rejected"]
        let rows: [[String: Any]] = statuses.enumerated().map { index, status in
            ["id": UUID().uuidString, "user_id": OiTestBackend.owner.uuidString, "status": status,
             "object_path": "synthetic-private.png", "submitted_at": "2026-11-0\(index + 1)T10:56:00Z",
             "review_note": status == "changes_requested" ? "기부처와 이체 완료 상태가 보이도록 다시 제출해 주세요." : ""]
        }
        let bytes = try JSONSerialization.data(withJSONObject: rows)
        OiStoreURLProtocol.handle = { request, client in
            if request.url?.path == "/rest/v1/oi_evidence_requests" { client.respond(200, bytes) }
            else { fallback?(request, client) }
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: config)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DonationEvidence-\(UUID())")
        defer {
            session.invalidateAndCancel(); OiStoreURLProtocol.handle = previous
            fixture.defaults.removePersistentDomain(forName: fixture.name)
            withExtendedLifetime(backend) {}
            if FileManager.default.fileExists(atPath: directory.path) { try? FileManager.default.removeItem(at: directory) }
        }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let remote = OiRemoteStore(api: api, drafts: OiDraftVault(directory: directory), vault: OiMemorySession())
        await remote.start()
        XCTAssertEqual(remote.evidence.count, 4)
        XCTAssertNotNil(UIImage(named: "DonationSeed"))
        XCTAssertNotNil(UIImage(named: "DonationApprovalBackground"))
        for variant in variants {
            let view = NavigationStack { OiDonationEvidenceView(remote: remote) }
            try await capture(view, name: "donation-evidence", variant: variant, defaults: fixture.defaults, attach: true)
            let attached = OiDonationEvidenceContent(evidence: [], attachmentName: "synthetic-proof.pdf",
                canSubmit: true, message: "파일은 아직 전송되지 않았어요")
            try await capture(attached, name: "donation-evidence-attached", variant: variant,
                defaults: fixture.defaults, attach: true)
            if variant.name == "402x874" {
                let review = OiDonationEvidenceReview(reviewType: "donation_evidence", evidenceId: UUID(),
                    submittedAt: "2026-11-05T00:00:00Z", analyzedAt: "2026-11-05T00:01:00Z",
                    humanReviewRequired: true, authenticityVerified: false, notice: "운영자 검토 후 작성 승인이 부여됩니다.",
                    assessment: .init(verdict: .inconclusive, readability: .limited, findings: [],
                        limitations: ["원본 진위와 실제 납입을 확인하지 못했어요."], manualChecks: ["기부처와 이체 완료 상태를 확인해 주세요."]))
                let result = OiDonationEvidenceContent(evidence: [], review: review)
                try await capture(result, name: "donation-evidence-ai-result", variant: variant,
                    defaults: fixture.defaults, attach: true)
                let failed = OiDonationEvidenceContent(evidence: remote.evidence,
                    message: "증빙은 접수됐지만 AI 검사를 완료하지 못했어요. AI 검사만 다시 시도해 주세요.")
                try await capture(failed, name: "donation-evidence-ai-error", variant: variant,
                    defaults: fixture.defaults, attach: true)
            }
        }
    }

    func testDonationSemanticResultCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let cases: [(name: String, outcome: OiDonationEvidenceSummary.Outcome?, title: String, reason: String)] = [
            ("sms-sufficient", .sufficientEvidence, "문자에서 기부 완료 근거를 확인했어요", "공식 발신번호와 입금 확인 내용을 함께 대조했어요. 영수증이 없어도 증빙으로 인정할 수 있어요."),
            ("pledge-insufficient", .needsMoreEvidence, "약정 접수만으로는 입금 완료를 확인하기 어려워요", "현재 자료에는 약정 접수 안내만 있어요. 입금 확인 문자나 이체 완료 내역을 추가해 주세요."),
            ("manipulation", .suspectedManipulation, "자료의 일부에 추가 확인이 필요해요", "문자 일부의 시각적 불일치를 확인했어요. 개인정보 가림 자체는 조작으로 판단하지 않아요."),
            ("duplicate", .duplicateEvidence, "다른 신청에 사용된 자료와 중복 근거가 있어요", "자료 재사용 가능성이 있어 운영자 확인이 필요해요. 다른 사용자의 정보는 표시하지 않아요."),
            ("legacy", nil, "이전 시각적 참고 검사", "")
        ]
        for variant in variants {
            for item in cases {
                var review = OiDonationEvidenceReview(reviewType: "donation_evidence", evidenceId: UUID(),
                    submittedAt: "2026-11-05T00:00:00Z", analyzedAt: "2026-11-05T00:01:00Z",
                    humanReviewRequired: true, authenticityVerified: false,
                    notice: "증빙 충족 판정은 학교의 공식 납입 확인이나 글 작성 승인이 아니에요.",
                    assessment: .init(verdict: item.outcome == .suspectedManipulation ? .suspicious : .noObviousSigns,
                        readability: .readable, findings: [], limitations: ["제출 자료의 원본 진위와 제출자 본인 여부는 별도 확인이 필요해요."],
                        manualChecks: ["운영자 검토 후 최종 작성 승인 상태를 확인해 주세요."]))
                if let outcome = item.outcome {
                    review.summary = .init(outcome: outcome, sufficientEvidence: outcome == .sufficientEvidence,
                        title: item.title, reasons: [item.reason], checks: [
                            .init(kind: "sender", status: "matched", detail: "실제 발신번호를 공식 기부 문의 번호와 대조했어요."),
                            .init(kind: "duplicate", status: outcome == .duplicateEvidence ? "duplicate" : "clear",
                                detail: outcome == .duplicateEvidence ? "다른 신청에서 동일한 자료의 사용 기록을 확인했어요." : "현재 확인 가능한 범위에서 다른 신청과의 중복 근거가 없어요.")
                        ], sourceReferences: [
                            .init(id: "postech-giving", url: "https://vision.postech.ac.kr/web/?sub=contract&top=participation",
                                title: "POSTECH 발전기금 공식 안내", kind: "official", verifiedAt: "2026-11-05")
                        ])
                }
                let screen = ScrollView {
                    OiDonationEvidenceResult(review: review).padding(20)
                }.background(Color.white).foregroundStyle(.black)
                try await capture(screen, name: "donation-semantic-" + item.name,
                    variant: variant, defaults: fixture.defaults, attach: true)
            }
        }
    }

    func testMYHouseArtworkDoesNotRevealImageMatte() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let variant = Variant(name: "124x124", size: CGSize(width: 124, height: 124), dynamicTypeSize: .large)
        for isPressed in [false, true] {
            let artwork = CampusMyHouseButtonStyle().makeBody(label: CampusMyHouseButtonArtwork(), isPressed: isPressed)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.74, green: 0.82, blue: 0.66))
            let png = try await capture(artwork, name: isPressed ? "my-house-pressed" : "my-house-idle",
                                        variant: variant, defaults: fixture.defaults, includesSafeArea: false)
            let bitmap = try renderedBitmap(png, size: variant.size)
            let pixels = try XCTUnwrap(bitmap.data).bindMemory(to: UInt8.self, capacity: 124 * 124 * 4)
            for y in [40, 82] {
                // Both samples are inside the circle, on opposite sides of the PNG's left edge.
                let outside = (y * 124 + 21) * 4
                let inside = (y * 124 + 23) * 4
                XCTAssertGreaterThan(Int(pixels[outside]) - Int(pixels[0]), 30,
                                     "The sampled edge must be within the cream button, not the page background")
                for channel in 0..<3 {
                    XCTAssertLessThanOrEqual(abs(Int(pixels[outside + channel]) - Int(pixels[inside + channel])), 8,
                                             "The source image matte must blend through its edge (pressed: \(isPressed))")
                }
            }
        }
    }

    func testStoryWritingCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            for bottom in [false, true] {
                let page = CreationCapturePage(step: 2, anchor: bottom ? .bottom : .top) {
                    StoryWritingCapture(draft: Self.draft)
                }
                try await capture(page, name: "writing\(bottom ? "-bottom" : "")", variant: variant, defaults: fixture.defaults)
            }
        }
    }

    func testStoryFieldsGrowAfterPastingMultipleLines() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ScrollView { StoryPasteFixture() })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
            previousKeyWindow?.makeKey()
        }

        let pasteboard = UIPasteboard.general
        let previousItems = pasteboard.items
        defer { pasteboard.items = previousItems }
        let pastedText = "캠퍼스의 봄\n친구와 걷던 길\n함께 남긴 이야기"

        func editors(in view: UIView) -> [UITextView] {
            if let editor = view as? UITextView { return [editor] }
            return view.subviews.flatMap { editors(in: $0) }
        }

        try await Task.sleep(for: .milliseconds(300))
        let fields = editors(in: host.view).sorted { $0.convert(.zero, to: host.view).minY < $1.convert(.zero, to: host.view).minY }
        XCTAssertEqual(fields.count, 2)
        for field in fields {
            XCTAssertTrue(field.becomeFirstResponder())
            try await Task.sleep(for: .milliseconds(300))
            let initialHeight = field.bounds.height
            XCTAssertGreaterThan(initialHeight, 0)
            pasteboard.string = pastedText
            field.paste(nil)
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(field.text, pastedText)
            XCTAssertGreaterThan(field.bounds.height, initialHeight + 20)
            XCTAssertFalse(field.isScrollEnabled)
            field.resignFirstResponder()
        }
    }

    private struct StoryPasteFixture: View {
        @State private var draft = OiStoryDraft()
        @FocusState private var focusedField: OiStoryWritingStep.Field?

        var body: some View {
            OiStoryWritingStep(draft: $draft, grants: [], focusedField: $focusedField)
        }
    }

    private struct StoryWritingCapture: View {
        let draft: OiStoryDraft
        @FocusState private var focusedField: OiStoryWritingStep.Field?

        var body: some View {
            VStack(alignment: .leading, spacing: 50) {
                OiStoryWritingStep(draft: .constant(draft), grants: [], focusedField: $focusedField)
                OiStoryAttachmentSections(photoCount: 0, latitude: draft.latitude,
                    longitude: draft.longitude, onPhotos: {}, onLocation: {})
            }
        }
    }

    func testPopulatedPhotoAndLocationCaptures() async throws {
        let fixture = try isolatedDefaults()
        let backend = OiTestBackend(); backend.install()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appending(path: "PhotoLocation-\(UUID())")
        defer {
            withExtendedLifetime(backend) {}
            session.invalidateAndCancel(); OiStoreURLProtocol.handle = nil
            fixture.defaults.removePersistentDomain(forName: fixture.name)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
                                 drafts: OiDraftVault(directory: directory), vault: OiMemorySession())
        await store.start()
        let first = UUID(), second = UUID()
        try await store.saveLocalPhoto(XCTUnwrap(UIImage(named: "DonationCampus")?.jpegData(compressionQuality: 0.9)),
                                       id: first, owner: OiTestBackend.owner)
        try await store.saveLocalPhoto(XCTUnwrap(UIImage(named: "CampusSchoolMap")?.jpegData(compressionQuality: 0.9)),
                                       id: second, owner: OiTestBackend.owner)
        for variant in variants {
            for step in [OiCreationStep.photos, .location] {
                // Capture the production editor route rather than a mocked form wrapper.
                if step == .location && variant.dynamicTypeSize == .accessibility5 { continue }
                var draft = Self.draft; draft.id = UUID()
                draft.latitude = 36.01261057021347; draft.longitude = 129.3197268697784
                let local = OiLocalDraft(draft: draft, photos: [first, second], version: 1, creationStep: step.rawValue)
                try await store.saveLocalDraft(local, owner: OiTestBackend.owner)
                let editor = NavigationStack {
                    OiStoryEditor(remote: store, localID: local.id).environment(\.scenePhase, .active)
                }
                try await capture(editor, name: step == .photos ? "photo-populated" : "location-search-entry",
                                  variant: variant, defaults: fixture.defaults, delay: .seconds(3), attach: true)
            }
        }
    }

    func testExpandedCostumeSetCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        var customization = Self.customization
        var look = OiWardrobeLook(); look.costume = .baseball
        customization.wardrobe = look
        for variant in variants.prefix(2) {
            for bottom in [false, true] {
                let page = CreationCapturePage(step: 3, anchor: bottom ? .bottom : .top) {
                    OiCucumberCustomizationStep(draft: .constant(Self.draft), customization: .constant(customization),
                        assets: Self.assets, canContinue: true, onContinue: {})
                        .environment(\.scenePhase, .active)
                }
                try await capture(page, name: bottom ? "costume-set-bottom" : "costume-set-top",
                                  variant: variant, defaults: fixture.defaults, delay: .seconds(3), attach: true)
            }
        }
    }

    func testCustomizationCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            let cucumber = CreationCapturePage(step: 3) {
                OiCucumberCustomizationStep(draft: .constant(Self.draft), customization: .constant(Self.customization),
                    assets: Self.assets, canContinue: true, onContinue: {})
                    .environment(\.scenePhase, .active)
            }
            try await capture(cucumber, name: "cucumber-customization", variant: variant, defaults: fixture.defaults, delay: .seconds(2))
            let card = CreationCapturePage(step: 4) {
                OiCardCustomizationStep(draft: .constant(Self.draft), customization: .constant(Self.customization),
                    assets: Self.assets, canContinue: true, onContinue: {})
            }
            try await capture(card, name: "card-customization", variant: variant, defaults: fixture.defaults)
        }
    }

    func testCropToolbarContrastCapture() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let image = try XCTUnwrap(UIImage(named: "DonationCampus"))
        // Reproduce the light parent and inherited black tint of the creation flow.
        let crop = OiPhotoCropEditor(image: image, apply: { _ in })
            .tint(.black).environment(\.colorScheme, .light)
        try await capture(crop, name: "crop-toolbar-contrast", variant: variants[0],
                          defaults: fixture.defaults, attach: true)
    }

    func testStoryListSeedUICaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        XCTAssertNotNil(UIImage(named: "StorySeedIcon"))
        for variant in variants {
            let reference = NavigationStack {
                OiStoryListView(state: .preview, seedCount: 3,
                    notices: OiStoryListView.listNotices,
                    guidance: OiStoryListView.listGuidance,
                    onAddSeed: {}, onCreateStory: {}, onUseSeed: {})
            }
            try await capture(reference, name: "story-list-seed-reference", variant: variant,
                              defaults: fixture.defaults, attach: true)
            // The actual screen displays zero until a seed service is connected.
            let store = OiRemoteStore(vault: OiMemorySession())
            let live = NavigationStack { OiStoryListScreen(remote: store) }
            try await capture(live, name: "story-list-seed-unconnected", variant: variant,
                              defaults: fixture.defaults, attach: true)
        }
    }

    func testUpdatedConsentCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            let page = VStack(spacing: 0) {
                OiCreationProgressHeader(step: 1).padding(.horizontal, 20)
                OiStoryConsentView(clauses: OiStoryConsentClause.figmaDrafts, showsHeader: false)
            }
            try await capture(page, name: "consent-three-clauses", variant: variant,
                              defaults: fixture.defaults, attach: true)
        }
    }

    func testFinishedCustomizationAndConsentCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            let cucumber = CreationCapturePage(step: 3, showsNavigation: true) {
                OiCucumberCustomizationStep(draft: .constant(Self.draft), customization: .constant(Self.customization),
                    assets: Self.assets, isFinished: true, onContinue: {})
                    .environment(\.scenePhase, .active)
            }
            try await capture(cucumber, name: "cucumber-finished", variant: variant, defaults: fixture.defaults, delay: .seconds(2), attach: true)
            let card = CreationCapturePage(step: 4, showsNavigation: true) {
                OiCardCustomizationStep(draft: .constant(Self.draft), customization: .constant(Self.customization),
                    assets: Self.assets, isFinished: true, onContinue: {})
            }
            try await capture(card, name: "card-finished", variant: variant, defaults: fixture.defaults, attach: true)
            try await capture(NavigationStack { OiStoryConsentView(clauses: OiStoryConsentClause.figmaDrafts) },
                name: "consent-footprints", variant: variant, defaults: fixture.defaults, attach: true)
        }
    }

    func testLocationSearchFirstCapture() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            let picker = OiLocationPicker(latitude: .constant(nil), longitude: .constant(nil))
            try await capture(picker, name: "location-search-first", variant: variant,
                defaults: fixture.defaults, attach: true)
        }
    }

    func testThreeDimensionalLocationPickerCapture() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let picker = OiLocationPicker(latitude: .constant(36.01261057021347), longitude: .constant(129.3197268697784), focusPlaceID: "53")
            .environment(\.scenePhase, .active)
        try await capture(picker, name: "location-3D-picker", variant: try XCTUnwrap(variants.first),
            defaults: fixture.defaults, delay: .seconds(3), attach: true)
    }

    func testSharedCardAndCollectionResultCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            let card = VStack {
                MYCardArtwork(card: Self.card).frame(maxWidth: 320)
            }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color("OiLight"))
            try await capture(card, name: "story-card", variant: variant, defaults: fixture.defaults)
            let result = ARCollectionResultView(name: Self.draft.cucumberName, tags: ["고마움", "우정"],
                donor: "검증용 농부", location: "POSTECH 지곡회관 · 연못", date: "2026.11.03",
                isCollected: false, onCollect: {}, onCancel: {}) {
                    OiStoryCardArtwork(name: Self.draft.cucumberName, introduction: Self.draft.body,
                        donor: "검증용 농부", date: "2026.11.03", tags: ["고마움", "우정"], assetName: "OiCats")
                }
            try await capture(result, name: "collection-result", variant: variant, defaults: fixture.defaults)
        }
    }

    func testCardRequestInboxCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let now = Date.now
        let rows = [
            OiCardRequestInboxItem(id: UUID(), requesterName: "검증용 농부", storyTitle: "캠퍼스에 남긴 이야기",
                schoolName: "POSTECH", portraitURL: nil, createdAt: now.addingTimeInterval(-180)),
            OiCardRequestInboxItem(id: UUID(), requesterName: "검증용 농부", storyTitle: "같은 농부가 요청한 또 다른 카드",
                schoolName: nil, portraitURL: nil, createdAt: now.addingTimeInterval(-1_620)),
            OiCardRequestInboxItem(id: UUID(), requesterName: "긴 닉네임의 검증용 농부", storyTitle: "긴 카드 제목을 줄이지 않고 보여주는지 확인하는 이야기",
                schoolName: nil, portraitURL: nil, createdAt: now.addingTimeInterval(-86_400)),
            OiCardRequestInboxItem(id: UUID(), requesterName: "검증용 농부", storyTitle: "가장 오래된 카드 요청",
                schoolName: nil, portraitURL: nil, createdAt: now.addingTimeInterval(-1_468_800))
        ]
        let states: [(name: String, rows: [OiCardRequestInboxItem], error: String?)] = [
            ("card-requests-inbox", rows, nil),
            ("card-requests-empty", [], nil),
            ("card-requests-error", [], "연결을 확인한 뒤 다시 시도해 주세요.")
        ]
        for variant in variants {
            for state in states {
                let inbox = OiCardRequestInboxView(requests: state.rows, isLoading: false, loadError: state.error,
                    pendingRequestID: nil, actionError: nil, onReload: {}, onDecision: { _, _ in })
                try await capture(inbox, name: state.name, variant: variant, defaults: fixture.defaults, attach: true)
            }
        }
        // Compare the sheet content at the Figma node's own dimensions. The
        // dark backing makes its 70% fill visible without depending on live map data.
        let sheetVariant = Variant(name: "402x803-sheet", size: CGSize(width: 402, height: 803), dynamicTypeSize: .large)
        let emptySheet = OiCardRequestInboxView(requests: [], isLoading: false, loadError: nil,
            pendingRequestID: nil, actionError: nil, onReload: {}, onDecision: { _, _ in })
        try await capture(emptySheet.background(Color(white: 0.117)), name: "card-requests-empty",
            variant: sheetVariant, defaults: fixture.defaults, includesSafeArea: false, attach: true)

        let reference = try XCTUnwrap(variants.first)
        let unconfirmed = OiCardRequestInboxView(requests: [], isLoading: false, loadError: nil,
            pendingRequestID: nil, actionError: "처리 결과를 확인하지 못했어요. 같은 응답을 다시 확인해 주세요.",
            onReload: {}, onDecision: { _, _ in }, onRetryDecision: {})
        try await capture(unconfirmed, name: "card-requests-unconfirmed-decision",
            variant: reference, defaults: fixture.defaults, attach: true)
    }

    func testEvidenceDesignPreviewCapture() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        for variant in variants {
            try await capture(NavigationStack { OiEvidenceDesignPreview() },
                              name: "evidence-preview", variant: variant, defaults: fixture.defaults, attach: true)
        }
    }

    func testMYScreenCapturesWithoutRemoteStore() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let library = MYLibraryStore()
        library.synchronize(nickname: "검증용 농부", cards: [], favorites: [])
        for variant in variants {
            let workshop = NavigationStack {
                MYWorkshopView(demo: library, remote: nil)
            }
            try await capture(workshop, name: "my-workshop", variant: variant, defaults: fixture.defaults)
            let farmer = NavigationStack { MYFarmerCustomizationView(remote: nil) }
            try await capture(farmer, name: "my-farmer", variant: variant, defaults: fixture.defaults)
            let settings = NavigationStack {
                MYSettingsView(demo: library, remote: nil)
            }
            try await capture(settings, name: "my-settings", variant: variant, defaults: fixture.defaults)
        }
    }

    func testMYCollectionCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let collectionStore = StoryCollectionStore(defaults: fixture.defaults)
        let collectionVariants = variants + [Variant(name: "small-accessibility5", size: CGSize(width: 375, height: 667), dynamicTypeSize: .accessibility5)]
        for populated in [false, true] {
            for filter in MYCollectionFilter.allCases {
                let library = MYLibraryStore()
                let cards = populated ? (0..<7).map { index in
                    MYCard(id: "my-capture-\(index)", title: "검증용 오이 \(index + 1)", image: "OiCats",
                        school: .postech, order: index, body: Self.draft.body, donor: "검증용 농부", date: "2026.11.05")
                } : []
                library.synchronize(nickname: "검증용 농부", cards: cards, favorites: [])
                library.collectionFilter = filter
                for variant in collectionVariants {
                    let view = NavigationStack {
                        MYCollectionView(demo: library, storyRepository: AppContainer.preview.storyRepository,
                            collectionStore: collectionStore)
                    }
                    try await capture(view, name: "my-collection-\(filter == .all ? "all" : "schools")-\(populated ? "content" : "empty")",
                        variant: variant, defaults: fixture.defaults, attach: true)
                }
                if filter == .schools {
                    for variant in collectionVariants {
                        let view = NavigationStack {
                            MYCollectionView(demo: library, school: .postech, storyRepository: AppContainer.preview.storyRepository,
                                collectionStore: collectionStore)
                        }
                        try await capture(view, name: "my-collection-school-\(populated ? "content" : "empty")",
                            variant: variant, defaults: fixture.defaults, attach: true)
                    }
                }
            }
        }
    }

    func testFarmerWardrobeAssetsAndSelectionContract() throws {
        let wardrobe = try MYFarmerWardrobe.loaded.get()
        XCTAssertEqual(wardrobe.items.count, 120)
        XCTAssertEqual(wardrobe.items.filter { $0.character == "kyu" }.count, 64)
        XCTAssertEqual(wardrobe.items.filter { $0.character == "cumber" }.count, 56)
        XCTAssertEqual(wardrobe.items.filter { !$0.wearables.isEmpty }.count, 117)
        XCTAssertFalse(wardrobe.items(character: "kyu", slot: .accessory).contains { $0.id == "kyu-3927-3879" })
        XCTAssertFalse(wardrobe.items(character: "cumber", slot: .set).contains { $0.id == "cumber-4148-5133" })
        XCTAssertFalse(wardrobe.items(character: "cumber", slot: .accessory).contains { $0.id == "cumber-4148-5283" })
        let canvases = Array(wardrobe.bodies.values) + wardrobe.items.flatMap { [$0.thumbnail] + $0.wearables }
        for canvas in canvases {
            XCTAssertGreaterThan(canvas.width, 0)
            XCTAssertGreaterThan(canvas.height, 0)
            XCTAssertFalse(canvas.layers.isEmpty)
            for layer in canvas.layers {
                XCTAssertNotNil(UIImage(named: layer.asset), "Missing bundled original: \(layer.asset)")
                XCTAssertGreaterThan(layer.width, 0)
                XCTAssertGreaterThan(layer.height, 0)
                for matrix in [layer.matrix, layer.crop] {
                    XCTAssertEqual(matrix.count, 2)
                    XCTAssertTrue(matrix.allSatisfy { $0.count == 3 && $0.allSatisfy(\.isFinite) })
                    let transform = MYFarmerCanvasArtwork.transform(matrix)
                    XCTAssertGreaterThan(abs(transform.a * transform.d - transform.b * transform.c), 0.000001)
                }
            }
        }
        XCTAssertTrue(wardrobe.validates(.legacy(.classic)))
        XCTAssertTrue(wardrobe.validates(.legacy(.casual)))
        XCTAssertFalse(wardrobe.validates(OiFarmerOutfit(character: "other", slots: [:])))
        for character in ["kyu", "cumber"] {
            let top = try XCTUnwrap(wardrobe.items(character: character, slot: .top).first)
            let bottom = try XCTUnwrap(wardrobe.items(character: character, slot: .bottom).first)
            let set = try XCTUnwrap(wardrobe.items(character: character, slot: .set).first)
            let initial = OiFarmerOutfit(character: character, slots: [:])
            let separates = initial.selecting(top).selecting(bottom)
            XCTAssertTrue(wardrobe.validates(separates))
            XCTAssertEqual(separates.slots.count, 2)
            let onePiece = separates.selecting(set)
            XCTAssertEqual(onePiece.slots, ["set": set.id])
            XCTAssertEqual(onePiece.selecting(top).slots, ["top": top.id])
            XCTAssertFalse(wardrobe.validates(OiFarmerOutfit(character: character, slots: ["shoes": top.id])))
        }
    }

    func testFarmerWearableAndThumbnailContactSheets() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let wardrobe = try MYFarmerWardrobe.loaded.get()
        for character in ["kyu", "cumber"] {
            for slot in [MYFarmerSlot.top, .bottom, .shoes, .set, .accessory] {
                let items = wardrobe.items(character: character, slot: slot)
                let rows = (items.count + 1) / 2
                let variant = Variant(name: "contact", size: CGSize(width: 402, height: CGFloat(rows * 180 + 28)), dynamicTypeSize: .large)
                let gallery = LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(items) { item in
                        VStack(spacing: 4) {
                            HStack(spacing: 8) {
                                MYFarmerLayeredArtwork(outfit: OiFarmerOutfit(character: character, slots: [slot.rawValue: item.id]), wardrobe: wardrobe)
                                    .frame(width: 90, height: 125)
                                Color.clear.frame(width: 60, height: 72)
                                    .overlay(alignment: .topLeading) {
                                        MYFarmerCanvasArtwork(canvas: item.thumbnail)
                                            .scaleEffect(60 / item.thumbnail.width, anchor: .topLeading)
                                    }.clipped()
                            }
                            Text(item.name).font(.system(size: 12)).multilineTextAlignment(.center).frame(height: 35)
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(.white)
                try await capture(gallery, name: "farmer-\(character)-\(slot.rawValue)", variant: variant,
                    defaults: fixture.defaults, includesSafeArea: false, attach: true)
            }
        }
    }

    func testEmptyCollectionCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let collectionStore = StoryCollectionStore(defaults: fixture.defaults)
        XCTAssertTrue(collectionStore.cards.isEmpty)
        XCTAssertNil(collectionStore.persistenceError)
        XCTAssertNotNil(UIImage(named: "MYEmptyCollection"))

        for filter in [MYCollectionFilter.all, .schools] {
            let library = MYLibraryStore()
            library.collectionFilter = filter
            let name = filter == .all ? "my-collection-empty" : "my-collection-schools-empty"
            for variant in variants {
                let collection = NavigationStack {
                    MYCollectionView(demo: library, storyRepository: UnconnectedPilotRepository(),
                        collectionStore: collectionStore)
                }
                try await capture(collection, name: name, variant: variant, defaults: fixture.defaults, attach: true)
            }
        }
    }

    func testCampusSearchStatesDoNotConfusePromptFailureAndEmptyResults() {
        for hasMatches in [false, true] {
            XCTAssertEqual(CampusSearchContentState(hasSearched: false, hasMatches: hasMatches,
                hasLoaded: false, isLoading: true, hasError: false), .prompt)
        }
        XCTAssertEqual(CampusSearchContentState(hasSearched: true, hasMatches: false,
            hasLoaded: false, isLoading: false, hasError: false), .loading)
        XCTAssertEqual(CampusSearchContentState(hasSearched: true, hasMatches: false,
            hasLoaded: true, isLoading: true, hasError: false), .loading)
        for hasLoaded in [false, true] {
            XCTAssertEqual(CampusSearchContentState(hasSearched: true, hasMatches: false,
                hasLoaded: hasLoaded, isLoading: false, hasError: true), .failed)
        }
        XCTAssertEqual(CampusSearchContentState(hasSearched: true, hasMatches: true,
            hasLoaded: true, isLoading: false, hasError: true), .results)
        XCTAssertEqual(CampusSearchContentState(hasSearched: true, hasMatches: false,
            hasLoaded: true, isLoading: false, hasError: false), .noMatches)
    }

    func testCampusSearchPromptCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let story = CampusStory(id: "prompt-fixture", regionID: "pond", title: "테스트오이", image: "OiCats",
            tags: [], donor: "가상 기부자", location: "테스트", date: "", order: 0, popularity: 0, palette: 0)
        for mode in CampusSearchMode.allCases {
            for variant in variants {
                let screen = CampusSearchView(mode: mode, entries: [.example(story)], isExample: false,
                    onSelect: { _ in XCTFail("No search has been submitted") })
                let png = try await capture(screen, name: "campus-search-\(mode.rawValue)-prompt", variant: variant,
                    defaults: fixture.defaults, attach: true)
                if variant.name == "402x874" {
                    let bitmap = try renderedBitmap(png, size: variant.size)
                    let pixels = try XCTUnwrap(bitmap.data).bindMemory(to: UInt8.self, capacity: bitmap.width * bitmap.height * 4)
                    var greenPixels = 0
                    for y in 250..<800 {
                        for x in 20..<382 {
                            let i = (y * bitmap.width + x) * 4
                            let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                            if g > r + 12 && g > b + 25 { greenPixels += 1 }
                        }
                    }
                    XCTAssertGreaterThan(greenPixels, 2500, "The initial screen must actually render the green cucumber, not only text")
                }
            }
        }
    }

    func testCampusSearchEmptyResultCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        XCTAssertNotNil(UIImage(named: "CampusSearchNoResults"))

        for mode in CampusSearchMode.allCases {
            let query = CampusSearchQuery(text: "없는 오이", name: "없는 농부")
            for variant in variants {
                let result = CampusSearchView(mode: mode, entries: [], isExample: false, initialQuery: query,
                    onSelect: { _ in XCTFail("Empty search must offer no selection") })
                try await capture(result, name: "campus-search-\(mode.rawValue)-no-matches", variant: variant,
                    defaults: fixture.defaults, attach: true)
            }
        }
    }

    func testSchoolSearchEmptyResultCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        XCTAssertNotNil(UIImage(named: "CampusSearchNoResults"))
        for variant in variants {
            let screen = CampusSchoolSearchView(initialQuery: "없는 학교") {
                XCTFail("A school with no matching result must not be selected")
            }
            let png = try await capture(screen, name: "school-search-no-matches", variant: variant,
                defaults: fixture.defaults, attach: true)
            if variant.name == "402x874" {
                let bitmap = try renderedBitmap(png, size: variant.size)
                let pixels = try XCTUnwrap(bitmap.data).bindMemory(to: UInt8.self, capacity: bitmap.width * bitmap.height * 4)
                var greenPixels = 0
                for y in 280..<610 {
                    for x in 100..<302 {
                        let i = (y * bitmap.width + x) * 4
                        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                        if g > r + 12 && g > b + 25 { greenPixels += 1 }
                    }
                }
                XCTAssertGreaterThan(greenPixels, 2500, "The school empty state must render its original cucumber illustration")
            }
        }
        let reference = try XCTUnwrap(variants.first)
        for (name, query) in [("initial", ""), ("matched", "postech")] {
            try await capture(CampusSchoolSearchView(initialQuery: query, onSelect: {}),
                name: "school-search-\(name)", variant: reference, defaults: fixture.defaults, attach: true)
        }
    }

    func testLocationSearchEmptyResultCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let query = "location-fixture-no-match"
        let places = try CampusMapData.load().pois
        XCTAssertFalse(places.isEmpty)
        XCTAssertFalse(places.contains { $0.name.localizedCaseInsensitiveContains(query) })

        for variant in variants {
            let location = OiStoryLocationStep(initialQuery: query, choose: { _ in })
            try await capture(location, name: "location-search-no-matches", variant: variant,
                defaults: fixture.defaults, attach: true)
        }
    }

    func testMYSettingsCapturesWithOfflineAccounts() async throws {
        let fixture = try isolatedDefaults()
        let previousHandler = OiStoreURLProtocol.handle
        let backend = OiTestBackend()
        backend.configure { profile in
            profile.nickname = "검증용 농부"
            profile.schoolID = "postech"
            profile.schoolProfileEnabled = true
            profile.farmerOutfitEnabled = true
            profile.farmName = "오이농장주인"
        }
        backend.install()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MYSettings-\(UUID().uuidString)", isDirectory: true)
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.name)
            withExtendedLifetime(backend) {}
            session.invalidateAndCancel()
            OiStoreURLProtocol.handle = previousHandler
            if FileManager.default.fileExists(atPath: directory.path) {
                XCTAssertNoThrow(try FileManager.default.removeItem(at: directory))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }

        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let signedIn = OiRemoteStore(api: api,
            drafts: OiDraftVault(directory: directory.appendingPathComponent("signed-in", isDirectory: true)),
            vault: OiMemorySession())
        let emptySession = OiMemorySession()
        try emptySession.write(nil)
        let signedOut = OiRemoteStore(api: api,
            drafts: OiDraftVault(directory: directory.appendingPathComponent("signed-out", isDirectory: true)),
            vault: emptySession)
        await signedIn.start()
        await signedOut.start()
        XCTAssertTrue(signedIn.hasLoadedRemote)
        XCTAssertTrue(signedIn.isFarmerOutfitAvailable)
        XCTAssertEqual(signedIn.profile?.nickname, "검증용 농부")
        XCTAssertEqual(signedIn.profile?.schoolId, "postech")
        XCTAssertTrue(signedOut.hasLoadedRemote)
        XCTAssertTrue(signedOut.isConfigured)
        XCTAssertNil(signedOut.account)

        for variant in variants {
            let workshop = NavigationStack { MYWorkshopView(demo: MYLibraryStore(), remote: signedIn) }
            try await capture(workshop, name: "my-workshop-signed-in", variant: variant, defaults: fixture.defaults, attach: true)
            let farmer = NavigationStack { MYFarmerCustomizationView(remote: signedIn) }
            try await capture(farmer, name: "my-farmer-signed-in", variant: variant, defaults: fixture.defaults, attach: true)
            let settings = NavigationStack(path: .constant([true])) {
                Color.white.navigationDestination(for: Bool.self) { _ in
                    MYSettingsView(remote: signedIn).environment(\.scenePhase, .active)
                }
            }
            try await capture(settings, name: "my-settings-signed-in", variant: variant,
                defaults: fixture.defaults, delay: .milliseconds(450), attach: true)

            let signIn = NavigationStack(path: .constant([true])) {
                Color.white.navigationDestination(for: Bool.self) { _ in
                    MYSettingsView(remote: signedOut).environment(\.scenePhase, .active)
                }
            }
            try await capture(signIn, name: "my-settings-signed-out-auth", variant: variant,
                defaults: fixture.defaults, delay: .milliseconds(450), attach: true)
        }

        let reference = try XCTUnwrap(variants.first)
        let account = NavigationStack(path: .constant([true])) {
            Color.white.navigationDestination(for: Bool.self) { _ in
                MYSettingsView(remote: signedIn).defaultScrollAnchor(.bottom).environment(\.scenePhase, .active)
            }
        }
        try await capture(account, name: "my-settings-signed-in-auth", variant: reference,
            defaults: fixture.defaults, delay: .milliseconds(450), attach: true)
        let steps: [(String, OiSchoolEvidenceView.Step)] = [
            ("profile", .profile), ("affiliation", .affiliation),
            ("student-document", .document(.student)), ("graduate-document", .document(.graduate)),
            ("attachment", .attachment(.graduate, .diploma))
        ]
        for variant in variants {
            for (name, step) in steps {
                let screen = NavigationStack {
                    OiSchoolEvidenceView(remote: signedIn, initialStep: step)
                }
                try await capture(screen, name: "school-evidence-" + name, variant: variant,
                    defaults: fixture.defaults, delay: .milliseconds(450), attach: true)
            }
        }
    }

    func testCampusDetailAndSummaryCaptures() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let store = CampusStoryStore(defaults: fixture.defaults, isExample: true)
        store.synchronize(stories: CampusStoryExamples.stories, collected: [])
        let story = try XCTUnwrap(store.stories.first)
        XCTAssertTrue(story.isExample)
        XCTAssertTrue(story.remoteMediaPaths.isEmpty, "This capture must use only bundled example images")
        XCTAssertNil(story.latitude, "The example must not start a live MapKit tile request")
        XCTAssertNil(story.longitude)
        for variant in variants {
            for bottom in [false, true] {
                let detail = NavigationStack {
                    CampusStoryDetailView(story: story, store: store)
                        .defaultScrollAnchor(bottom ? .bottom : .top)
                }
                try await capture(detail, name: "campus-detail\(bottom ? "-bottom" : "")",
                    variant: variant, defaults: fixture.defaults)
            }
            let summary = NavigationStack {
                CampusSummaryView(story: story, store: store).environment(\.scenePhase, .active)
            }
            try await capture(summary, name: "campus-summary", variant: variant,
                defaults: fixture.defaults, delay: .seconds(2))
        }
    }

    func testCampusSummaryShowsActionForVerifiedLocation() async throws {
        let fixture = try isolatedDefaults()
        let previousHandler = OiStoreURLProtocol.handle
        let backend = OiTestBackend()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory.appending(path: "CampusCardLocation-\(UUID())")
        defer {
            fixture.defaults.removePersistentDomain(forName: fixture.name)
            withExtendedLifetime(backend) {}
            session.invalidateAndCancel()
            OiStoreURLProtocol.handle = previousHandler
            if FileManager.default.fileExists(atPath: directory.path) {
                XCTAssertNoThrow(try FileManager.default.removeItem(at: directory))
            }
        }
        var draft = Self.draft
        draft.grantId = OiTestBackend.grant
        draft.latitude = 36.01261057021347
        draft.longitude = 129.3197268697784
        var published = try draft.payload()
        published["user_id"] = OiTestBackend.owner.uuidString
        published["status"] = "published"
        published["created_at"] = "2026-10-28T00:00:00Z"
        backend.configure { $0.story = published }
        backend.install()
        let vault = OiMemorySession()
        try vault.write(nil)
        let remote = OiRemoteStore(api: try OiServiceAPI(key: "sb_publishable_testing", session: session),
            drafts: OiDraftVault(directory: directory), vault: vault)
        await remote.start()
        let story = remote.campusStory(try XCTUnwrap(remote.stories.first))
        let store = CampusStoryStore(defaults: fixture.defaults)
        store.synchronize(stories: [story], collected: [])
        let reference = try XCTUnwrap(variants.first)
        let states: [(String, CampusCardProximity?)] = [
            ("pohang-collect", .near),
            ("outside-pohang-request", .away),
            ("unknown-location-request", nil)
        ]
        for (name, proximity) in states {
            let summary = NavigationStack { CampusSummaryView(story: story, store: store) }
                .environment(remote)
                .environment(\.campusCardProximity) { _ in
                    guard let proximity else { throw CampusCardLocationError.permissionDenied }
                    return proximity
                }
                .environment(\.scenePhase, .active)
            try await capture(summary, name: name, variant: reference,
                defaults: fixture.defaults, delay: .seconds(2), attach: true)
        }
        XCTAssertTrue(backend.snapshot().cardSendPayloads.isEmpty, "Checking the location must not send a request")
    }

    func testFarmCapturesWithOfflineOwnedStory() async throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let previousHandler = OiStoreURLProtocol.handle
        let backend = OiTestBackend()
        backend.configure { $0.nickname = "공개 작성자"; $0.farmName = "햇살" }
        backend.install()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OiStoreURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Figma132-Farm-\(UUID().uuidString)", isDirectory: true)
        defer {
            withExtendedLifetime(backend) {}
            session.invalidateAndCancel()
            OiStoreURLProtocol.handle = previousHandler
            if FileManager.default.fileExists(atPath: directory.path) {
                XCTAssertNoThrow(try FileManager.default.removeItem(at: directory))
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        }
        let api = try OiServiceAPI(key: "sb_publishable_testing", session: session)
        let remote = OiRemoteStore(api: api, drafts: OiDraftVault(directory: directory), vault: OiMemorySession())
        await remote.start()
        XCTAssertTrue(remote.hasLoadedRemote)
        XCTAssertEqual(remote.account?.id, OiTestBackend.owner)
        XCTAssertTrue(remote.ownStories.isEmpty)
        for variant in variants {
            let empty = NavigationStack { MYFarmView(remote: remote) }
            try await capture(empty, name: "my-farm-empty", variant: variant, defaults: fixture.defaults)
        }
        var draft = Self.draft
        draft.grantId = OiTestBackend.grant
        draft.latitude = 36.01261057021347
        draft.longitude = 129.3197268697784
        let receipt = await remote.save(draft)
        let saved = try XCTUnwrap(receipt, "The existing offline mutation path must create the owned story")
        XCTAssertEqual(saved.status, "draft")
        XCTAssertEqual(remote.ownStories.map(\.id), [saved.id])
        for variant in variants {
            let populated = NavigationStack { MYFarmView(remote: remote) }
            try await capture(populated, name: "my-farm-populated", variant: variant, defaults: fixture.defaults)
        }
    }

    func testFarmerAppearancePersistsForItsOwnerOnly() throws {
        let fixture = try isolatedDefaults()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.name) }
        let firstOwner = OiTestBackend.owner
        let secondOwner = OiTestBackend.other
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: firstOwner, defaults: fixture.defaults), .classic)
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: secondOwner, defaults: fixture.defaults), .classic)
        MYFarmerAppearanceStore.save(.casual, ownerID: firstOwner, defaults: fixture.defaults)
        let restoredDefaults = try XCTUnwrap(UserDefaults(suiteName: fixture.name))
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: firstOwner, defaults: restoredDefaults), .casual)
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: secondOwner, defaults: restoredDefaults), .classic)
        MYFarmerAppearanceStore.save(.classic, ownerID: secondOwner, defaults: fixture.defaults)
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: firstOwner, defaults: restoredDefaults), .casual)
        MYFarmerAppearanceStore.save(.casual, ownerID: nil, defaults: fixture.defaults)
        XCTAssertNil(fixture.defaults.object(forKey: MYFarmerAppearanceStore.key(ownerID: nil)))
        XCTAssertEqual(MYFarmerAppearanceStore.read(ownerID: nil, defaults: restoredDefaults), .classic)
    }

    @discardableResult
    private func capture<V: View>(_ view: V, name: String, variant: Variant, defaults: UserDefaults,
                                 includesSafeArea: Bool = true,
                                 delay: Duration = .milliseconds(180), attach: Bool = false) async throws -> Data {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first, "The isolated simulator test host must have a window scene")
        let existingWindows = scene.windows.map { (id: ObjectIdentifier($0), hidden: $0.isHidden, key: $0.isKeyWindow) }
        let window = UIWindow(windowScene: scene)
        let windowID = ObjectIdentifier(window)
        let root = UIViewController()
        let host = UIHostingController(rootView: view
            .environment(\.dynamicTypeSize, variant.dynamicTypeSize)
            .environment(\.colorScheme, .light)
            .defaultAppStorage(defaults))
        if !includesSafeArea { host.safeAreaRegions = [] }
        window.frame = CGRect(origin: .zero, size: variant.size)
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = root
        root.view.frame = window.bounds
        root.addChild(host)
        host.view.frame = root.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.view.addSubview(host.view)
        host.didMove(toParent: root)
        // Showing this owned window without making it key preserves all existing windows.
        window.isHidden = false
        defer {
            releaseCampusRenderers(in: host.view)
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            window.isHidden = true
            window.rootViewController = nil
            window.windowScene = nil
            XCTAssertFalse(scene.windows.contains { ObjectIdentifier($0) == windowID }, "The capture window must detach, including hidden windows")
            for previous in existingWindows {
                if let existing = scene.windows.first(where: { ObjectIdentifier($0) == previous.id }) {
                    XCTAssertEqual(existing.isHidden, previous.hidden, "A pre-existing test-host window must retain its visibility")
                    XCTAssertEqual(existing.isKeyWindow, previous.key, "A capture must never take key-window ownership")
                }
            }
        }
        window.layoutIfNeeded()
        root.view.layoutIfNeeded()
        host.view.setNeedsLayout()
        try await Task.sleep(for: delay)
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        var rendered = false
        let png = UIGraphicsImageRenderer(size: variant.size, format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: variant.size))
            rendered = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(rendered, "The attached production view must draw its hierarchy")
        try assertNonemptyRender(png, size: variant.size)
        if attach {
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "\(name)-\(variant.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let directory = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("Figma132", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("\(name)-\(variant.name).png")
        try png.write(to: output, options: .atomic)
        XCTAssertEqual(try Data(contentsOf: output).count, png.count, "The saved capture must contain the rendered PNG")
        print("Figma132 capture: \(output.path)")
        return png
    }

    private func releaseCampusRenderers(in view: UIView) {
        if let canvas = view as? CampusMapCanvas {
            canvas.removeRenderer()
            XCTAssertNil(canvas.map, "The owned summary renderer must be released before the next capture")
        }
        for child in view.subviews { releaseCampusRenderers(in: child) }
    }

    private func assertNonemptyRender(_ data: Data, size: CGSize) throws {
        let context = try renderedBitmap(data, size: size)
        let bytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: context.width * context.height * 4)
        var colors = Set<UInt32>()
        for y in stride(from: 0, to: context.height, by: 8) {
            for x in stride(from: 0, to: context.width, by: 8) {
                let offset = (y * context.width + x) * 4
                colors.insert(UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
                    | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3]))
            }
        }
        XCTAssertGreaterThan(colors.count, 8, "A blank or uniform host is not a valid capture of these views")
    }

    private func renderedBitmap(_ data: Data, size: CGSize) throws -> CGContext {
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        XCTAssertEqual(image.width, Int(size.width))
        XCTAssertEqual(image.height, Int(size.height))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context
    }

    private func isolatedDefaults() throws -> (name: String, defaults: UserDefaults) {
        let name = "OiFigmaFidelityVisualTests.\(UUID().uuidString)"
        return (name, try XCTUnwrap(UserDefaults(suiteName: name)))
    }

    private static var draft: OiStoryDraft {
        var draft = OiStoryDraft()
        draft.title = "시각 검증용 이야기"
        draft.body = "함께한 순간을 캠퍼스에 남기는 화면 검증용 문장입니다. 이 자료는 테스트에만 사용되며 서버로 제출하지 않습니다."
        draft.theme = "우정"
        draft.emotion = "고마움"
        draft.cucumberName = "검증용오이"
        return draft
    }

    private static var customization: OiDraftCustomization {
        var customization = OiDraftCustomization()
        customization.fill = .gradient
        customization.firstColor = 0xD3DBC4
        customization.secondColor = 0xF3F7E6
        return customization
    }

    private static let assets = [OiAsset(id: "OiCats", kind: "cucumber", name: "기본 세트"),
                                 OiAsset(id: "MYBasicCard", kind: "card", name: "기본 카드")]

    private static var card: MYCard {
        MYCard(id: "figma132-visual-fixture", title: draft.cucumberName, image: "OiCats", school: .postech,
            order: 0, body: draft.body, donor: "검증용 농부", date: "2026.11.03")
    }
}

private struct CreationCapturePage<Content: View>: View {
    let step: Int
    var anchor: UnitPoint = .top
    var showsNavigation = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            OiCreationProgressHeader(step: step, onPrevious: {})
                .padding(.horizontal, 20).padding(.top, 1).padding(.bottom, 29)
            Group {
                if step == 3 || step == 4 { content() }
                else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) { content() }
                            .padding(.horizontal, 20).padding(.bottom, 24)
                    }.defaultScrollAnchor(anchor)
                }
            }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if step == 2 || showsNavigation {
                        OiCreationNavigationBar(onPrevious: {}, onNext: {}, onSaveAndExit: {})
                    }
                }
        }.background(Color(.systemBackground))
    }
}
