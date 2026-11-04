//
//  CampusArtworkOverlay.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

import SwiftUI

struct CampusArtworkOverlay<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.clear.contentShape(Rectangle()).onTapGesture { dismiss() }
                .accessibilityHidden(true)
            ScrollView {
                content().frame(maxWidth: 362).padding(.horizontal, 20)
                    .frame(maxWidth: .infinity).padding(.vertical, 76)
            }
            .defaultScrollAnchor(.center)
            .scrollIndicators(.hidden)
            .accessibilityLabel(title)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }.buttonStyle(.glass).buttonBorderShape(.circle)
                .accessibilityLabel("확대 보기 닫기").padding(16)
        }
        .presentationBackground(.ultraThinMaterial)
    }
}
