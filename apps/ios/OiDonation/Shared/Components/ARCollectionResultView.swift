//
//  ARCollectionResultView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

import SwiftUI

/// The shared post-win layout. Persistence and artwork belong to the caller.
struct ARCollectionResultView<Artwork: View>: View {
    let name: String
    let tags: [String]
    let donor: String
    let location: String
    let date: String
    let isCollected: Bool
    var isSaving = false
    var canCollect = true
    var collectTitle = "도감 저장하기"
    var collectedTitle = "도감에 저장됨"
    var cancelTitle = "취소"
    var accessibilityPrefix = "collection.result"
    var notice: String? = nil
    let onCollect: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let artwork: () -> Artwork

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 34) {
                    artwork()
                        .aspectRatio(320 / 444, contentMode: .fit)
                        .frame(width: min(320, geometry.size.width - 32))
                        .compositingGroup()
                        .shadow(color: .black.opacity(0.25), radius: 3.5, x: 3, y: 6)
                    summary
                        .frame(width: min(362, geometry.size.width - 40), height: usesExpandedLayout ? nil : 210)
                    if let notice {
                        Text(notice)
                            .font(.callout)
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 42)
                .padding(.bottom, max(34, geometry.safeAreaInsets.bottom + 8))
            }
        }
        .background(Color(red: 243 / 255, green: 247 / 255, blue: 230 / 255).ignoresSafeArea())
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerLayout {
                Text(name)
                    .font(.custom("PearToucan-Bold", size: 28, relativeTo: .title))
                    .tracking(1.12)
                    .lineLimit(usesExpandedLayout ? nil : 1)
                    .minimumScaleFactor(0.65)
                    .fixedSize(horizontal: false, vertical: usesExpandedLayout)
                    .layoutPriority(1)
                tagLabels
            }
            metadata
            actionsLayout {
                Button(action: onCollect) {
                    HStack(spacing: 5) {
                        if isSaving {
                            ProgressView().tint(.white).accessibilityHidden(true)
                        } else {
                            if isCollected { Image(systemName: "checkmark") }
                            Text(isCollected ? collectedTitle : collectTitle)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: usesExpandedLayout)
                        }
                    }
                    .font(.custom("Paperlogy-6SemiBold", size: 14, relativeTo: .callout))
                    .foregroundStyle(.white)
                    .padding(.horizontal, usesExpandedLayout ? 12 : 0)
                    .padding(.vertical, usesExpandedLayout ? 12 : 0)
                    .frame(maxWidth: .infinity, minHeight: 44, maxHeight: usesExpandedLayout ? nil : 44)
                    .background(Color(red: 90 / 255, green: 112 / 255, blue: 51 / 255), in: RoundedRectangle(cornerRadius: 20))
                    .contentShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: usesExpandedLayout ? .infinity : 239)
                .disabled(!canCollect || isSaving)
                .accessibilityLabel(isCollected ? collectedTitle : collectTitle)
                .accessibilityValue(isSaving ? "저장 중" : "")
                .accessibilityIdentifier("\(accessibilityPrefix).collect")
                Button(action: onCancel) {
                    Text(cancelTitle)
                        .font(.custom("Paperlogy-6SemiBold", size: 14, relativeTo: .callout))
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: usesExpandedLayout)
                        .padding(.vertical, usesExpandedLayout ? 12 : 0)
                        .frame(maxWidth: usesExpandedLayout ? .infinity : nil, minHeight: 44)
                        .frame(width: usesExpandedLayout ? nil : 67)
                        .background(Color(white: 221 / 255), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .accessibilityIdentifier("\(accessibilityPrefix).cancel")
            }
        }
        .foregroundStyle(.black)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: usesExpandedLayout ? nil : .infinity)
        .background(.white, in: RoundedRectangle(cornerRadius: 30))
        .compositingGroup()
        .shadow(color: Color(red: 46 / 255, green: 79 / 255, blue: 22 / 255).opacity(0.4), radius: 5)
    }

    private var tagLabels: some View {
        tagsLayout {
            ForEach(Array(tags.prefix(2).enumerated()), id: \.offset) { _, tag in
                Text(tag.hasPrefix("#") ? tag : "#\(tag)")
                    .font(.custom("Paperlogy-4Regular", size: 16, relativeTo: .caption))
                    .tracking(0.32)
                    .foregroundStyle(Color(red: 191 / 255, green: 67 / 255, blue: 13 / 255))
                    .lineLimit(usesExpandedLayout ? nil : 1)
                    .fixedSize(horizontal: false, vertical: usesExpandedLayout)
            }
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            metadataRow("기부자", value: donor)
            metadataRow("위치", value: location)
            metadataRow("날짜", value: date)
        }
        .font(.custom("Paperlogy-2ExtraLight", size: 15, relativeTo: .caption))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        metadataLayout {
            Text(label)
            if !usesExpandedLayout { Text("|") }
            Text(value)
                .lineLimit(usesExpandedLayout ? nil : 1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: usesExpandedLayout)
        }
    }

    private var usesExpandedLayout: Bool { dynamicTypeSize > .large }
    private var headerLayout: AnyLayout {
        usesExpandedLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }
    private var actionsLayout: AnyLayout {
        usesExpandedLayout ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
    }
    private var tagsLayout: AnyLayout {
        usesExpandedLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
    }
    private var metadataLayout: AnyLayout {
        usesExpandedLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 5))
    }
}
