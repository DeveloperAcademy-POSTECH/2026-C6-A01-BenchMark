//
//  OiStoryCardArtwork.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/3/26.
//

import SwiftUI
import UIKit

/// A printed card composition. Its artwork scales as a unit; accessible story text
/// remains available through the combined label and the surrounding story screen.
struct OiStoryCardArtwork: View {
    let name: String
    let introduction: String
    let donor: String
    let date: String
    var tags: [String] = []
    var assetName: String? = nil
    var imageURL: URL? = nil
    var appearance = "MYBasicCard"
    var portrait: UIImage? = nil
    var portraitPath: String? = nil
    var expectsPortrait = false
    var loadPortrait: ((String) async throws -> UIImage)? = nil

    private var hasCustomPortrait: Bool { portrait != nil || portraitPath != nil || expectsPortrait }

    var body: some View {
        GeometryReader { geometry in
            composition
                .frame(width: 362, height: 502)
                .scaleEffect(geometry.size.width / 362, anchor: .topLeading)
        }
        .aspectRatio(362 / 502, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([name, tags.joined(separator: ", "), introduction, donor, date]
            .filter { !$0.isEmpty }.joined(separator: ". "))
    }

    private var composition: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 15)
                .fill(LinearGradient(colors: [.init(white: 234 / 255), .init(white: 203 / 255)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))

            ZStack(alignment: .topLeading) {
                Image("OiStoryCardTexture").resizable().scaledToFill()
                    .frame(width: 332, height: 472).opacity(0.7)
                tint.opacity(0.18)
                if hasCustomPortrait {
                    character.frame(width: 290, height: 351).offset(x: 21, y: 42)
                        .frame(width: 332, height: 472, alignment: .topLeading)
                } else {
                    character.frame(width: 439, height: 688).offset(x: -60, y: -24)
                        .frame(width: 332, height: 472, alignment: .topLeading)
                }
                LinearGradient(colors: [.clear, .clear, .black.opacity(0.72)],
                               startPoint: .top, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 10) {
                    Spacer(minLength: 0)
                    Text(introduction)
                        .font(.custom("Paperlogy-4Regular", size: 16))
                        .tracking(0.48).lineSpacing(3).lineLimit(3)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(Array(tags.prefix(2).enumerated()), id: \.offset) { _, tag in
                                Text(tag).font(.custom("Paperlogy-4Regular", size: 10))
                                    .lineLimit(1).padding(.horizontal, 8).padding(.vertical, 4)
                                    .foregroundStyle(.black).background(.white, in: Capsule())
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Image("OiStoryCardMark").resizable().scaledToFit()
                            .frame(width: 14, height: 13).padding(3)
                            .background(Color(red: 250 / 255, green: 244 / 255, blue: 220 / 255),
                                        in: RoundedRectangle(cornerRadius: 4))
                        Text(donor).font(.custom("Paperlogy-4Regular", size: 10))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                        // This is the source artwork's decorative wave, not an NFC action.
                        Image(systemName: "wave.3.right").font(.system(size: 23, weight: .semibold))
                    }.foregroundStyle(.white)
                }.padding(.horizontal, 14).padding(.bottom, 10).padding(.top, 42)
                    .frame(width: 332, height: 472)

                Image("OiStoryCardHeader").resizable().frame(width: 268, height: 36)
                Image("OiStoryCardFrame").resizable().frame(width: 332, height: 472)
                Text("STORY").font(.custom("Paperlogy-7Bold", size: 11))
                    .foregroundStyle(Color(red: 128 / 255, green: 110 / 255, blue: 63 / 255))
                    .frame(width: 62, height: 36)
                Text(name).font(.custom("Paperlogy-3Light", size: 19)).tracking(1.52)
                    .lineLimit(1).minimumScaleFactor(0.55)
                    .frame(width: 180, height: 36, alignment: .leading).offset(x: 77)
            }
            .frame(width: 332, height: 472)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .offset(x: 15, y: 15)

            Text(["OI Donation", date].filter { !$0.isEmpty }.joined(separator: " / "))
                .font(.custom("Paperlogy-4Regular", size: 7)).lineLimit(1)
                .minimumScaleFactor(0.7).foregroundStyle(.black)
                .frame(width: 332, height: 14).offset(x: 15, y: 487)
        }
        .dynamicTypeSize(.medium)
        .clipped()
    }

    @ViewBuilder private var character: some View {
        if let portrait {
            Image(uiImage: portrait).resizable().scaledToFit()
        } else if let portraitPath, let loadPortrait {
            OiCucumberPortraitImage(path: portraitPath, load: loadPortrait)
        } else if let assetName, !hasCustomPortrait {
            Image(assetName == "OiCats" || assetName == "OiCatsPortrait" ? "OiStoryCardCats" : assetName)
                .resizable().scaledToFill()
        } else if let imageURL, imageURL.isFileURL,
                  let image = UIImage(contentsOfFile: imageURL.path) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: hasCustomPortrait ? .fit : .fill)
        } else if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: hasCustomPortrait ? .fit : .fill)
                case .empty: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .failure: unavailableCharacter
                @unknown default: unavailableCharacter
                }
            }
        } else {
            unavailableCharacter
        }
    }

    private var unavailableCharacter: some View {
        Image(systemName: "leaf").font(.system(size: 70, weight: .light))
            .foregroundStyle(.white.opacity(0.65)).frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private var tint: Color {
        switch appearance {
        case "MYBlueCard": Color(red: 0.55, green: 0.74, blue: 0.96)
        case "MYRedCard": Color(red: 0.95, green: 0.56, blue: 0.52)
        default: .clear
        }
    }
}

/// Match the loaded image to the snapshot path, including while a reused card changes stories.
struct OiCucumberPortraitImage: View {
    let path: String
    let load: (String) async throws -> UIImage
    @State private var result: (path: String, image: UIImage?)?

    var body: some View {
        Group {
            if let result, result.path == path {
                if let image = result.image { Image(uiImage: image).resizable().scaledToFit() }
                else { Image(systemName: "leaf").foregroundStyle(.secondary).accessibilityLabel("꾸민 오이 이미지를 불러오지 못했어요") }
            } else { ProgressView().accessibilityLabel("꾸민 오이 불러오는 중") }
        }
        .task(id: path) {
            do {
                let image = try await load(path)
                try Task.checkCancellation()
                result = (path, image)
            } catch {
                if !Task.isCancelled { result = (path, nil) }
            }
        }
    }
}
