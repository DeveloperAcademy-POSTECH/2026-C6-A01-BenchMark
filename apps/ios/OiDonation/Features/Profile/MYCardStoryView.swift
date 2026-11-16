//
//  MYCardStoryView.swift
//  OiDonation
//
//  Created by 이돈혁 on 10/28/26.
//

import SwiftUI

struct MYCardStoryView: View {
    let card: MYCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MYCardArtwork(card: card).frame(maxHeight: 502)
                    .frame(maxWidth: .infinity).accessibilityLabel("\(card.title) 카드")
                Text(card.title).font(CampusStyle.heading(28))
                Text(card.school.rawValue).font(.headline)
                Text(card.body)
                    .font(.body).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle("카드 이야기").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).toolbarRole(.navigationStack)
    }
}
