//
//  OiCardRequestInboxView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/4/26.
//

import SwiftUI

struct OiCardRequestInboxItem: Identifiable, Equatable {
    let id: UUID
    let requesterName: String
    let storyTitle: String
    let schoolName: String?
    let portraitURL: URL?
    let createdAt: Date
}

enum OiCardRequestDecision: String {
    case accept
    case reject

    var label: LocalizedStringKey {
        switch self {
        case .accept: "수락"
        case .reject: "거절"
        }
    }
}

struct OiCardRequestInboxView: View {
    let requests: [OiCardRequestInboxItem]
    let isLoading: Bool
    let loadError: String?
    let pendingRequestID: UUID?
    let actionError: String?
    let onReload: () async -> Void
    let onDecision: (UUID, OiCardRequestDecision) async -> Void
    var onRetryDecision: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var headerHeight = 33
    @ScaledMetric(relativeTo: .body) private var emptyParagraphSpacing = 31.5
    @State private var confirmation: Confirmation?
    @State private var didAttemptLoad = false

    private struct Confirmation {
        let request: OiCardRequestInboxItem
        let decision: OiCardRequestDecision
    }

    private static let darkGreen = Color(red: 39 / 255, green: 49 / 255, blue: 22 / 255)
    private static let rejectGreen = Color(red: 176 / 255, green: 202 / 255, blue: 170 / 255)
    private static let acceptGreen = Color(red: 105 / 255, green: 175 / 255, blue: 88 / 255)

    var body: some View {
        GeometryReader { viewport in
            inboxScrollView(minimumHeight: viewport.size.height + viewport.safeAreaInsets.bottom)
        }
        .accessibilityIdentifier("oi.cardRequests.inbox")
        .refreshable { await onReload() }
        .task {
            await onReload()
            if !Task.isCancelled { didAttemptLoad = true }
        }
        .background(sheetBackground.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationCornerRadius(35)
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
        .presentationContentInteraction(.scrolls)
        .alert(
            confirmation?.decision == .reject ? "카드 요청을 거절할까요?" : "카드 요청을 수락할까요?",
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            presenting: confirmation
        ) { selection in
            Button("취소", role: .cancel) {}
            Button(selection.decision.label, role: selection.decision == .reject ? .destructive : nil) {
                Task { await onDecision(selection.request.id, selection.decision) }
            }
        } message: { selection in
            Text("\(selection.request.requesterName) 님이 ‘\(selection.request.storyTitle)’ 카드를 요청했어요.")
        }
    }

    private var sheetBackground: Color {
        let tint = colorScheme == .dark ? Self.darkGreen : CampusStyle.mapSheet
        // Figma uses a 70% green fill, without a second material layer.
        return tint.opacity(reduceTransparency || colorSchemeContrast == .increased ? 1 : 0.7)
    }

    private var showsEmptyState: Bool {
        didAttemptLoad && !isLoading && requests.isEmpty && pendingRequestID == nil
            && loadError == nil && actionError == nil && onRetryDecision == nil
    }

    private func inboxScrollView(minimumHeight: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let actionError {
                    Label(actionError, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("oi.cardRequests.decisionError")
                }
                if let onRetryDecision {
                    Button("처리 결과 다시 확인") { Task { await onRetryDecision() } }
                        .buttonStyle(.bordered)
                        .disabled(isLoading || pendingRequestID != nil)
                        .accessibilityIdentifier("oi.cardRequests.retryDecision")
                }
                if let pendingRequestID, !requests.contains(where: { $0.id == pendingRequestID }) {
                    ProgressView().accessibilityLabel("요청을 처리하는 중이에요")
                }
                if let loadError {
                    loadFailure(loadError)
                }
                if requests.isEmpty && pendingRequestID == nil {
                    if isLoading || (!didAttemptLoad && loadError == nil) {
                        ProgressView().accessibilityLabel("카드 요청을 불러오는 중이에요")
                            .frame(maxWidth: .infinity, minHeight: 150)
                    } else if showsEmptyState {
                        emptyState
                            // Keep the message centered in the space below the header,
                            // including the home-indicator area, as in the 402 × 803 sheet.
                            .frame(minHeight: max(0, minimumHeight - 20 - headerHeight - 20))
                    }
                } else {
                    LazyVStack(spacing: 26) {
                        ForEach(requests) { request in requestRow(request) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, showsEmptyState ? 0 : 20)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectHidden()
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: emptyParagraphSpacing) {
                Text("아직 받은 요청이 없습니다")
                Text("동문들과 친구들의 오이를 살펴보고\n카드를 요청해보세요!")
            }
            .font(CampusStyle.medium(21))
            .tracking(0.42)
            .lineHeight(.exact(points: emptyParagraphSpacing))
            .foregroundStyle(colorScheme == .dark || colorSchemeContrast == .increased
                ? Color.primary : Color("OiGreen"))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("oi.cardRequests.empty")
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        Text("카드 요청")
            // The 30-day retention notice is intentionally excluded (2026-11-05).
            // Keep the inbox title and an explicit accessible dismiss control.
            .font(CampusStyle.medium(16))
            .tracking(0.32)
            .foregroundStyle(colorScheme == .dark ? Color.white : Self.darkGreen)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .leading)
            .padding(.trailing, 52)
            .accessibilityAddTraits(.isHeader)
            .overlay(alignment: .trailing) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(pendingRequestID != nil)
                .accessibilityLabel("카드 요청 닫기")
            }
    }

    private func loadFailure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("카드 요청을 불러오지 못했어요", systemImage: "exclamationmark.circle")
                .font(.headline)
            Text(message).font(.footnote)
            Button("다시 시도") { Task { await onReload() } }
                .buttonStyle(.bordered)
                .disabled(isLoading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("oi.cardRequests.loadError")
    }

    private func requestRow(_ request: OiCardRequestInboxItem) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 12) {
                portrait(for: request.portraitURL)
                VStack(alignment: .leading, spacing: 2) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            requestContext(request)
                            Spacer(minLength: 0)
                            requestTime(request.createdAt)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            requestContext(request)
                            requestTime(request.createdAt)
                        }
                    }
                    Text(request.requesterName)
                        .font(.custom("Paperlogy-6SemiBold", size: 22, relativeTo: .title2))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .combine)

            if pendingRequestID == request.id {
                ProgressView().accessibilityLabel("요청을 처리하는 중이에요")
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    decisionButton(.reject, for: request, fill: Self.rejectGreen)
                    decisionButton(.accept, for: request, fill: Self.acceptGreen)
                }
                .disabled(pendingRequestID != nil || isLoading || loadError != nil || onRetryDecision != nil)
            }
        }
    }

    private func requestContext(_ request: OiCardRequestInboxItem) -> some View {
        Label {
            if let school = request.schoolName, !school.isEmpty {
                Text("\(school) · \(request.storyTitle)")
            } else {
                Text(request.storyTitle)
            }
        } icon: {
            Image(systemName: request.schoolName?.isEmpty == false ? "graduationcap.fill" : "rectangle.portrait")
        }
        .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
        .foregroundStyle(.secondary)
    }

    private func requestTime(_ date: Date) -> some View {
        let label = date.formatted(.relative(presentation: .numeric).locale(Locale(identifier: "ko_KR")))
        return Text(verbatim: label)
            .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func portrait(for url: URL?) -> some View {
        ZStack {
            Circle().fill(Self.rejectGreen.opacity(0.25))
            if let url, url.scheme?.lowercased() == "https" {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        defaultPortrait
                    }
                }
            } else {
                defaultPortrait
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Color("OiGreen"), lineWidth: 1) }
        .accessibilityHidden(true)
    }

    private var defaultPortrait: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(Color("OiGreen"))
    }

    private func decisionButton(
        _ decision: OiCardRequestDecision,
        for request: OiCardRequestInboxItem,
        fill: Color
    ) -> some View {
        Button {
            confirmation = Confirmation(request: request, decision: decision)
        } label: {
            Text(decision.label)
                .font(.custom("Paperlogy-5Medium", size: 14, relativeTo: .subheadline))
                .foregroundStyle(Self.darkGreen)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, minHeight: 35)
                .background(fill, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("\(request.requesterName) 님의 \(request.storyTitle) 카드 요청"))
        .accessibilityIdentifier("oi.cardRequests.\(decision.rawValue).\(request.id.uuidString)")
    }
}
