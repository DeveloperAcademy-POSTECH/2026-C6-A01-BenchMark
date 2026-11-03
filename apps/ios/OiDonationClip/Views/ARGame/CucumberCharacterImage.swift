//
//  CucumberCharacterImage.swift
//  OiDonationClip
//
//  Created by jiwon hong on 10/28/26.
//

import SwiftUI

struct CucumberCharacterImage: View {
    let imageURL: URL?
    let contentMode: ContentMode
    let isTemplate: Bool

    init(
        imageURL: URL?,
        contentMode: ContentMode,
        isTemplate: Bool = false
    ) {
        self.imageURL = imageURL
        self.contentMode = contentMode
        self.isTemplate = isTemplate
    }

    @State private var artwork: UIImage?

    var body: some View {
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .renderingMode(isTemplate ? .template : .original)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Color.clear
            }
        }
        .task(id: imageURL) {
            artwork = await CucumberArtwork.load(imageURL: nil)
            guard let imageURL else { return }
            let image = await CucumberArtwork.load(imageURL: imageURL)
            guard !Task.isCancelled else { return }
            artwork = image
        }
    }
}
