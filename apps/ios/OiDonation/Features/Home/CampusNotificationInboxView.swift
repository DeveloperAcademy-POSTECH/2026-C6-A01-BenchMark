//
//  CampusNotificationInboxView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/16/26.
//

import SwiftUI

struct OiContinuationNotice: Identifiable, Equatable {
    let id: UUID
    let title: String
    let author: String
    let createdAt: Date
    let isUnread: Bool
}

struct CampusNotificationInboxView: View {
    let requests: [OiCardRequestInboxItem]
    let isLoading: Bool
    var loadFailed = false
    var unconfirmedRequestID: UUID? = nil
    var onOpenOlderRequests: (() -> Void)? = nil
    let onReload: () async -> Void
    let onOpenRequest: (UUID) -> Void
    var continuations: [OiContinuationNotice] = []
    var onOpenContinuation: ((UUID) -> Void)? = nil
    var onMoreContinuations: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var emptyLineHeight = 31.5

    private var isEmpty: Bool {
        requests.isEmpty && continuations.isEmpty && unconfirmedRequestID == nil
    }

    private var showsSpinner: Bool {
        loadFailed || (isLoading && isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !showsSpinner { CampusNotificationRetentionNotice() }
            GeometryReader { viewport in
                ScrollView {
                    content
                        .frame(maxWidth: .infinity, minHeight: viewport.size.height,
                            alignment: showsSpinner || isEmpty ? .center : .top)
                }
                .refreshable { await onReload() }
            }
            if !showsSpinner, let onOpenOlderRequests {
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
            if showsSpinner {
                ProgressView()
                    .accessibilityLabel("알림을 불러오는 중이에요")
                    .accessibilityIdentifier("campus.notifications.loading")
            } else if isEmpty {
                Text("알림 없음")
                    .font(CampusStyle.medium(21))
                    .tracking(0.42)
                    .lineHeight(.exact(points: emptyLineHeight))
                    .foregroundStyle(colorScheme == .light && contrast == .standard
                        ? Color("OiGreen") : .primary)
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .accessibilityIdentifier("campus.notifications.empty")
            } else {
                requestList
            }
        }
    }

    private var requestList: some View {
        LazyVStack(spacing: 25) {
            if let unconfirmedRequestID, !requests.contains(where: { $0.id == unconfirmedRequestID }) {
                Button("카드 요청 처리 결과 확인") { onOpenRequest(unconfirmedRequestID) }
                    .buttonStyle(.bordered)
            }
            ForEach(requests) { request in
                requestRow(request)
                    .disabled(unconfirmedRequestID.map { $0 != request.id } ?? false)
            }
            ForEach(continuations) { notice in
                Button { onOpenContinuation?(notice.id) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("이어진 이야기 · \(notice.author)")
                            Spacer()
                            if notice.isUnread { Circle().fill(CampusStyle.green).frame(width: 7, height: 7) }
                        }.font(.caption).foregroundStyle(.secondary)
                        Text("내 이야기에서 새 이야기가 이어졌어요").font(CampusStyle.medium(16))
                        Text(notice.title).font(CampusStyle.body(18))
                        Text("공개된 이야기 연결 · 실제 납입 알림이 아니에요").font(.caption).foregroundStyle(.secondary)
                        requestDate(notice.createdAt).font(.caption).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading).padding(20)
                    .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).disabled(unconfirmedRequestID != nil)
                    .accessibilityIdentifier("campus.notifications.continuation.\(notice.id.uuidString)")
            }
            if let onMoreContinuations {
                Button("이어진 이야기 알림 더 보기", action: onMoreContinuations).disabled(unconfirmedRequestID != nil || isLoading)
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
        Text("최근 \(period) 동안의 알림을 표시해요")
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
    CampusNotificationInboxView(requests: [], isLoading: false,
        onReload: {}, onOpenRequest: { _ in })
}
