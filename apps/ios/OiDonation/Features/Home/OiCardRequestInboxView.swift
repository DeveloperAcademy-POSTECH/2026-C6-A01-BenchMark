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

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let actionError {
                    Label(actionError, systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("oi.cardRequests.decisionError")
                }
                if let loadError {
                    loadFailure(loadError)
                }
                if requests.isEmpty {
                    if isLoading || (!didAttemptLoad && loadError == nil) {
                        ProgressView("카드 요청을 불러오는 중이에요")
                            .frame(maxWidth: .infinity, minHeight: 150)
                    } else if loadError == nil {
                        ContentUnavailableView(
                            "받은 카드 요청이 없어요",
                            systemImage: "envelope",
                            description: Text("새 카드 요청이 오면 여기에 표시돼요.")
                        )
                    }
                } else {
                    LazyVStack(spacing: 26) {
                        ForEach(requests) { request in requestRow(request) }
                    }
                }
            }
            .padding(20)
        }
        .accessibilityIdentifier("oi.cardRequests.inbox")
        .refreshable { await onReload() }
        .task {
            await onReload()
            if !Task.isCancelled { didAttemptLoad = true }
        }
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .overlay {
                    (colorScheme == .dark
                        ? Self.darkGreen
                        : Color(red: 234 / 255, green: 238 / 255, blue: 226 / 255))
                        .opacity(0.7)
                }
                .ignoresSafeArea()
        }
        .presentationCornerRadius(35)
        .presentationBackground(.clear)
        .presentationDragIndicator(.visible)
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

    private var header: some View {
        Text("카드 요청")
            .font(.custom("Paperlogy-7Bold", size: 22, relativeTo: .title2))
            .foregroundStyle(colorScheme == .dark ? Color.white : Self.darkGreen)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 33, alignment: .leading)
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
                .accessibilityLabel("닫기")
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
                ProgressView("요청을 처리하는 중이에요")
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 4))
                    : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    decisionButton(.reject, for: request, fill: Self.rejectGreen)
                    decisionButton(.accept, for: request, fill: Self.acceptGreen)
                }
                .disabled(pendingRequestID != nil || isLoading || loadError != nil)
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
