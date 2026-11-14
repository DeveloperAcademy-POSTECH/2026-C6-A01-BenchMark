//
//  ScratchPostcardLoader.swift
//  OiDonationClip
//
//  Created by jiwon hong on 11/13/26.
//

import Observation
import SwiftUI
import UIKit

/// Everything the scratch postcard screen shows, loaded from the server for one NFC tag (#291).
struct ScratchPostcard {
    let tagID: String
    let story: Story
    let card: StoryCard
    let donorLine: String
    /// Approved postcard front. Nil for stories published without a card snapshot.
    let front: UIImage?
    /// Postcard back rendered by the app at submission. Nil for older stories; the text is drawn instead.
    let back: UIImage?
    /// Shown faintly on the card to scratch and uncovered by scratching.
    let coverPhoto: UIImage?
    let character: UIImage?

    /// Figma colours a trailing "오이" green, so split it off when the author's name ends with it.
    var nameParts: (lead: String, suffix: String) {
        let name = story.cucumberName
        guard name.hasSuffix("오이"), name.count > 2 else { return (name, "") }
        return (String(name.dropLast(2)), "오이")
    }

    var dateLine: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter.string(from: story.publishedAt)
    }
}

@MainActor
@Observable
final class ScratchPostcardLoader {
    enum State {
        case loading
        case loaded(ScratchPostcard)
        /// Unknown or retired tag, or a story that is no longer public.
        case unavailable
        case failed
    }

    private(set) var state: State = .loading
    private var requestID = UUID()

    func load(tag: String, repository: any StoryRepository) async {
        let current = UUID()
        requestID = current
        state = .loading
        do {
            guard let storyID = try await repository.fetchNFCPostcardStoryID(tag: tag),
                  let story = try await repository.fetchPublicStory(storyID: storyID),
                  let card = try await repository.fetchPublicStoryCard(storyID: storyID),
                  let details = try await repository.fetchPublicPostcardDetails(storyID: storyID) else {
                guard requestID == current, !Task.isCancelled else { return }
                state = .unavailable
                return
            }
            async let front = Self.image(details.frontURL)
            async let back = Self.image(details.backURL)
            async let character = try? Self.image(story.cucumberImageURL)
            let frontImage = try await front
            // The card to scratch shows the same picture as the approved front (#326). Only stories
            // without a postcard front fall back to their first photo.
            var cover = frontImage.flatMap(Self.postcardWindow)
            if cover == nil, frontImage == nil {
                cover = (try? await Self.image(details.coverPhotoURL)) ?? nil
            }
            let postcard = ScratchPostcard(
                tagID: tag, story: story, card: card,
                donorLine: details.donorLine ?? story.donorDisplayName,
                front: frontImage, back: try await back,
                coverPhoto: cover, character: await character ?? nil
            )
            guard requestID == current, !Task.isCancelled else { return }
            state = .loaded(postcard)
        } catch is CancellationError {
            return
        } catch {
            guard requestID == current, !Task.isCancelled else { return }
            state = .failed
        }
    }

    /// The 296×436 picture window at (33, 33) of the 362×502 postcard front.
    nonisolated static func postcardWindow(_ front: UIImage) -> UIImage? {
        guard let cg = front.cgImage, cg.width > 0, cg.height > 0 else { return nil }
        let sx = CGFloat(cg.width) / 362, sy = CGFloat(cg.height) / 502
        let rect = CGRect(x: 33 * sx, y: 33 * sy, width: 296 * sx, height: 436 * sy).integral
        guard let cropped = cg.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped, scale: front.scale, orientation: front.imageOrientation)
    }

    nonisolated private enum ImageError: Error { case rejected }
    nonisolated private static let maximumBytes = 10 * 1024 * 1024

    /// Downloads a signed storage image from the approved host, or reads a bundled preset portrait.
    nonisolated private static func image(_ url: URL?) async throws -> UIImage? {
        guard let url else { return nil }
        if url.isFileURL { return UIImage(contentsOfFile: url.path) }
        guard url.scheme == "https", url.host == "kfzfzarslqdqmrazohej.supabase.co" else { throw ImageError.rejected }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= maximumBytes,
              let image = UIImage(data: data) else { throw ImageError.rejected }
        return image
    }
}

/// Opens the postcard for an NFC tag: loading, unavailable and retry states around `ScratchPostcardView`.
struct ScratchPostcardScreen: View {
    let tagID: String
    let repository: any StoryRepository
    var onClose: () -> Void

    @State private var loader = ScratchPostcardLoader()
    @State private var attempt = 0

    var body: some View {
        Group {
            switch loader.state {
            case .loaded(let postcard):
                ScratchPostcardView(postcard: postcard, onClose: onClose,
                    validateCollection: { try await repository.canCollectNFCPostcard(tag: tagID, storyID: postcard.story.storyID) })
            case .loading:
                ProgressView("엽서를 불러오는 중")
                    .font(.custom("Paperlogy-4Regular", size: 15))
            case .unavailable:
                message("이 엽서는 지금 볼 수 없어요", detail: "공개가 끝났거나 연결이 바뀐 엽서예요.", retry: false)
            case .failed:
                message("엽서를 불러오지 못했어요", detail: "인터넷 연결을 확인하고 다시 시도해 주세요.", retry: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .task(id: attempt) { await loader.load(tag: tagID, repository: repository) }
    }

    private func message(_ title: String, detail: String, retry: Bool) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.custom("Paperlogy-6SemiBold", size: 18))
            Text(detail).font(.custom("Paperlogy-4Regular", size: 14)).foregroundStyle(.secondary)
            if retry {
                Button("다시 시도") { attempt += 1 }.frame(minHeight: 44)
            }
            Button("닫기", action: onClose).frame(minHeight: 44)
        }
        .multilineTextAlignment(.center)
        .padding(24)
    }
}

/// Stand-ins drawn when a story has no approved front or back image.
struct ScratchPostcardFallbackFront: View {
    let photo: UIImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Self.paper)
            Group {
                if let photo { Image(uiImage: photo).resizable().scaledToFill() } else { Color(red: 0.47, green: 0.51, blue: 0.36) }
            }
            .frame(width: 296, height: 436).clipped()
            .offset(x: 33, y: 33)
        }
        .frame(width: 362, height: 502)
        .modifier(PostcardCanvas())
    }

    static let paper = LinearGradient(colors: [Color(red: 232 / 255, green: 238 / 255, blue: 207 / 255),
                                               Color(red: 213 / 255, green: 219 / 255, blue: 198 / 255)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct ScratchPostcardFallbackBack: View {
    let message: String
    let author: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(ScratchPostcardFallbackFront.paper)
            Text(message.isEmpty ? "아직 남긴 이야기가 없어요." : message)
                .font(.custom("Paperlogy-4Regular", size: 17))
                .lineSpacing(8)
                .minimumScaleFactor(0.6)
                .frame(width: 292, height: 389, alignment: .topLeading)
                .offset(x: 35, y: 30)
            Text("FROM").font(.custom("Paperlogy-4Regular", size: 8)).offset(x: 35, y: 441)
            Text(author).font(.custom("Paperlogy-4Regular", size: 12)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: 292, height: 15, alignment: .leading).offset(x: 35, y: 457)
        }
        .foregroundStyle(Color(red: 50 / 255, green: 63 / 255, blue: 29 / 255))
        .frame(width: 362, height: 502)
        .modifier(PostcardCanvas())
    }
}

/// Draws a view built in the 362×502 postcard space at whatever size it is given.
private struct PostcardCanvas: ViewModifier {
    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content.scaleEffect(proxy.size.width / 362, anchor: .topLeading)
        }
        .aspectRatio(362.0 / 502.0, contentMode: .fit)
        .dynamicTypeSize(.medium)
    }
}
