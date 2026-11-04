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
    let assetName: String?

    init(
        imageURL: URL?,
        contentMode: ContentMode,
        isTemplate: Bool = false,
        assetName: String? = nil
    ) {
        self.imageURL = imageURL
        self.contentMode = contentMode
        self.isTemplate = isTemplate
        self.assetName = assetName
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
        .task(id: ArtworkRequest(imageURL: imageURL, assetName: assetName)) {
            artwork = await CucumberArtwork.load(imageURL: nil, assetName: assetName)
            guard let imageURL else { return }
            let image = await CucumberArtwork.load(imageURL: imageURL, assetName: assetName)
            guard !Task.isCancelled else { return }
            artwork = image
        }
    }

    private struct ArtworkRequest: Hashable {
        let imageURL: URL?
        let assetName: String?
    }
}
