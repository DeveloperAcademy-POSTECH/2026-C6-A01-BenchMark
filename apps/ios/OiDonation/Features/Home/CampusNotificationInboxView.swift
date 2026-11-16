//
//  CampusNotificationInboxView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/16/26.
//

import SwiftUI

struct CampusNotificationInboxView: View {
    let requests: [OiCardRequestInboxItem]
    let isLoading: Bool
    let loadError: String?
    var unconfirmedRequestID: UUID? = nil
    let onReload: () async -> Void
    let onOpenRequest: (UUID) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { viewport in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: viewport.size.height,
                        alignment: requests.isEmpty && unconfirmedRequestID == nil ? .center : .top)
            }
            .refreshable { await onReload() }
        }
        .accessibilityIdentifier("campus.notifications.inbox")
    }

    private var content: some View {
        Group {
            if let loadError, requests.isEmpty && unconfirmedRequestID == nil {
                ContentUnavailableView {
                    Label("알림을 불러오지 못했어요", systemImage: "exclamationmark.circle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("다시 시도") { Task { await onReload() } }
                        .buttonStyle(.bordered)
                }
                .accessibilityIdentifier("campus.notifications.loadError")
            } else if requests.isEmpty && unconfirmedRequestID == nil {
                if isLoading {
                    ProgressView("알림을 불러오는 중이에요")
                } else {
                    Text("알림 없음")
                        .font(CampusStyle.medium(21))
                        .tracking(0.42)
                        .foregroundStyle(colorScheme == .light && contrast == .standard
                            ? Color("OiGreen") : .primary)
                        .multilineTextAlignment(.center)
                        .padding(20)
                        .accessibilityIdentifier("campus.notifications.empty")
                }
            } else {
                requestList
            }
        }
    }

    private var requestList: some View {
        LazyVStack(spacing: 25) {
            if let loadError {
                VStack(alignment: .leading, spacing: 6) {
                    Label(loadError, systemImage: "exclamationmark.circle")
                    Button("다시 시도") { Task { await onReload() } }
                        .buttonStyle(.bordered)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("campus.notifications.loadError")
            }
            if let unconfirmedRequestID, !requests.contains(where: { $0.id == unconfirmedRequestID }) {
                Button("카드 요청 처리 결과 확인") { onOpenRequest(unconfirmedRequestID) }
                    .buttonStyle(.bordered)
            }
            ForEach(requests) { request in
                requestRow(request)
                    .disabled(unconfirmedRequestID.map { $0 != request.id } ?? false)
            }
        }
        .padding(20)
    }

    private func requestRow(_ request: OiCardRequestInboxItem) -> some View {
        Button { onOpenRequest(request.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text("카드 요청").fixedSize()
                        Spacer(minLength: 0)
                        requestDate(request.createdAt).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("카드 요청")
                        requestDate(request.createdAt)
                    }
                }
                .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
                .tracking(0.24)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.storyTitle)
                            .font(CampusStyle.body(18))
                            .tracking(0.36)
                        Text(request.requesterName)
                            .font(CampusStyle.body(14))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color(uiColor: .separator), lineWidth: 1 / displayScale)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("campus.notifications.request.\(request.id.uuidString)")
    }

    private func requestDate(_ date: Date) -> Text {
        Text(verbatim: date.formatted(.relative(presentation: .numeric).locale(Locale(identifier: "ko_KR"))))
    }
}

#Preview("Empty notifications") {
    CampusNotificationInboxView(requests: [], isLoading: false, loadError: nil,
        onReload: {}, onOpenRequest: { _ in })
}
