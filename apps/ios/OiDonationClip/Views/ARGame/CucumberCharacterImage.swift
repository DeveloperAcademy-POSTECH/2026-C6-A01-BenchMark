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

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        styled(image)
                    case .empty, .failure:
                        fallbackImage
                    @unknown default:
                        fallbackImage
                    }
                }
            } else {
                fallbackImage
            }
        }
        .aspectRatio(contentMode: contentMode)
    }

    private var fallbackImage: some View {
        styled(Image("ARGameIntroCucumber"))
    }

    private func styled(_ image: Image) -> some View {
        image
            .renderingMode(isTemplate ? .template : .original)
            .resizable()
    }
}
