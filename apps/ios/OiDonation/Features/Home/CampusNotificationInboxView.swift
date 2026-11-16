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
    var onOpenOlderRequests: (() -> Void)? = nil
    let onReload: () async -> Void
    let onOpenRequest: (UUID) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var emptyLineHeight = 31.5

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CampusNotificationRetentionNotice()
            GeometryReader { viewport in
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, minHeight: viewport.size.height,
                            alignment: requests.isEmpty && unconfirmedRequestID == nil ? .center : .top)
                }
                .refreshable { await onReload() }
            }
            if let onOpenOlderRequests {
                Button("이전 카드 요청 보기", action: onOpenOlderRequests)
                    .font(CampusStyle.medium(16))
                    .disabled(unconfirmedRequestID != nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 9)
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
                        .lineHeight(.exact(points: emptyLineHeight))
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
    }

    private func requestRow(_ request: OiCardRequestInboxItem) -> some View {
        Button { onOpenRequest(request.id) } label: {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        Text("카드 요청 · \(request.requesterName)").fixedSize()
                        Spacer(minLength: 0)
                        requestDate(request.createdAt).fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("카드 요청 · \(request.requesterName)")
                        requestDate(request.createdAt)
                    }
                }
                .font(.custom("Paperlogy-4Regular", size: 12, relativeTo: .caption))
                .tracking(0.24)
                .foregroundStyle(colorScheme == .light && contrast == .standard
                    ? Color(white: 157 / 255) : .secondary)

                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    Text(request.storyTitle)
                        .font(CampusStyle.body(18))
                        .tracking(0.36)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("응답 대기")
                        .font(CampusStyle.body(14))
                        .tracking(0.28)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .background(CampusStyle.mapSheet, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20))
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("campus.notifications.request.\(request.id.uuidString)")
    }

    private func requestDate(_ date: Date) -> Text {
        Text(verbatim: date.formatted(.relative(presentation: .numeric).locale(Locale(identifier: "ko_KR"))))
    }
}

struct CampusNotificationRetentionNotice: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var lineHeight = 24

    var body: some View {
        let period = Text("30일").font(.custom("Paperlogy-7Bold", size: 16, relativeTo: .body))
        Text("알림은 \(period)이 지나면 삭제됩니다")
            .font(CampusStyle.medium(16))
            .tracking(0.32)
            .lineHeight(.exact(points: lineHeight))
            .foregroundStyle(colorScheme == .light && contrast == .standard
                ? Color(white: 169 / 255) : .secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("campus.notifications.retention")
    }
}

#Preview("Empty notifications") {
    CampusNotificationInboxView(requests: [], isLoading: false, loadError: nil,
        onReload: {}, onOpenRequest: { _ in })
}
