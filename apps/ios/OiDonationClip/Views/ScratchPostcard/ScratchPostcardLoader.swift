//
//  ScratchPostcardLoader.swift
//  OiDonationClip
//
//  Created by jiwon hong on 11/13/26.
//

import ImageIO
import Observation
import StoreKit
import SwiftUI
import UIKit

/// Everything the scratch postcard screen shows, loaded from the server for one NFC tag (#291).
struct ScratchPostcard {
    let tagID: String
    let story: Story
    let card: StoryCard
    let donorLine: String
    /// Approved postcard front. Nil for stories published without a card snapshot.
    var front: UIImage?
    /// Postcard back rendered by the app at submission. Nil for older stories; the text is drawn instead.
    var back: UIImage?
    /// Shown faintly on the card to scratch and uncovered by scratching.
    let coverPhoto: UIImage?
    let character: UIImage?
    /// True while the front or back is still downloading behind an already scratchable card (#348).
    var isLoadingFaces = false

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

    /// `storyID` skips the tag lookup, for the full app opening a story's postcard straight from the map (#399).
    func load(tag: String, repository: any StoryRepository, storyID preselected: String? = nil) async {
        let current = UUID()
        requestID = current
        state = .loading
        do {
            let linked: String?
            if let preselected { linked = preselected } else { linked = try await repository.fetchNFCPostcardStoryID(tag: tag) }
            guard let storyID = linked,
                  let fetched = try await repository.fetchPublicPostcard(storyID: storyID) else {
                guard requestID == current, !Task.isCancelled else { return }
                state = .unavailable
                return
            }
            let story = fetched.story, details = fetched.details
            async let front = Self.image(details.frontURL)
            async let back = Self.image(details.backURL)
            async let cleanCover = try? Self.image(details.coverURL, coverType: details.coverType)
            async let character = try? Self.image(story.cucumberImageURL)
            // Prefer the reviewed sticker-free window. Older snapshots and unavailable covers
            // use the approved front window; only stories without a front use their first photo.
            var cover = await cleanCover ?? nil
            var frontImage: UIImage?
            var hasFront = false
            if cover == nil {
                frontImage = try await front
                hasFront = true
                cover = frontImage.flatMap(Self.postcardWindow)
                if cover == nil, frontImage == nil {
                    cover = (try? await Self.image(details.coverPhotoURL)) ?? nil
                }
            }
            // Scratching needs only the cover and the character, so the card appears while the
            // front and back keep downloading (#348).
            var postcard = ScratchPostcard(
                tagID: tag, story: story, card: fetched.card,
                donorLine: details.donorLine ?? story.donorDisplayName,
                front: frontImage, back: nil,
                coverPhoto: cover, character: await character ?? nil,
                isLoadingFaces: true
            )
            guard requestID == current, !Task.isCancelled else { return }
            state = .loaded(postcard)

            // A face that fails behind a visible card gets one more try before the screen resets.
            if !hasFront {
                do { postcard.front = try await front } catch is CancellationError { return }
                catch { postcard.front = try await Self.image(details.frontURL) }
            }
            do { postcard.back = try await back } catch is CancellationError { return }
            catch { postcard.back = try await Self.image(details.backURL) }
            postcard.isLoadingFaces = false
            guard requestID == current, !Task.isCancelled else { return }
            state = .loaded(postcard)
        } catch is CancellationError {
            return
        } catch {
            guard requestID == current, !Task.isCancelled else { return }
            state = .failed
        }
    }

    #if DEBUG
    /// Screenshot hook: launch with `OI_SCRATCH_POSTCARD_STATE=loading|unavailable|failed` to hold that state.
    static var debugState: State? {
        switch ProcessInfo.processInfo.environment["OI_SCRATCH_POSTCARD_STATE"] {
        case "loading": .loading
        case "unavailable": .unavailable
        case "failed": .failed
        default: nil
        }
    }

    func show(_ state: State) { self.state = state }
    #endif

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
    nonisolated private static func image(_ url: URL?, coverType: StoryCard.CoverType? = nil) async throws -> UIImage? {
        guard let url else { return nil }
        if url.isFileURL {
            let data = try Data(contentsOf: url)
            return try decodedImage(data, coverType: coverType)
        }
        guard url.scheme == "https", url.host == "kfzfzarslqdqmrazohej.supabase.co" else { throw ImageError.rejected }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ImageError.rejected }
        return try decodedImage(data, coverType: coverType)
    }

    nonisolated private static func decodedImage(_ data: Data, coverType: StoryCard.CoverType?) throws -> UIImage {
        guard !data.isEmpty, data.count <= (coverType?.maximumBytes ?? maximumBytes) else { throw ImageError.rejected }
        if let coverType {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetType(source) as String? == coverType.typeIdentifier,
                  CGImageSourceGetCount(source) == 1,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (1...2048).contains(width), (1...2048).contains(height) else { throw ImageError.rejected }
        }
        guard let image = UIImage(data: data) else { throw ImageError.rejected }
        return image
    }
}

/// Opens the postcard for an NFC tag: loading, unavailable and retry states around `ScratchPostcardView`.
struct ScratchPostcardScreen: View {
    let tagID: String
    let repository: any StoryRepository

    @State private var loader = ScratchPostcardLoader()
    @State private var attempt = 0
    @State private var showingFullAppOverlay = false

    var body: some View {
        Group {
            switch loader.state {
            case .loaded(let postcard):
                ScratchPostcardView(postcard: postcard,
                    validateCollection: { try await repository.canCollectNFCPostcard(tag: tagID, storyID: postcard.story.storyID) },
                    // A blocked author's postcard reloads into the unavailable state.
                    onBlock: { attempt += 1 })
            case .loading:
                ScratchPostcardStatusView(message: "엽서를 꺼내는 중이에요\n잠시만 기다려 주세요") {
                    ProgressView().tint(ScratchPostcardStatusView<EmptyView>.green)
                }
                .accessibilityLabel("엽서를 불러오는 중")
            case .unavailable:
                ScratchPostcardStatusView(message: "이 엽서는 지금 볼 수 없어요\n비공개·차단되었거나 연결이 바뀐 엽서예요") {
                    ScratchPostcardStatusButton(title: "전체 앱 보기") { showingFullAppOverlay = true }
                        .accessibilityHint("전체 앱 설치 안내를 열어요")
                }
            case .failed:
                ScratchPostcardStatusView(message: "엽서를 불러오지 못했어요\n인터넷 연결을 확인하고 다시 시도해 주세요") {
                    ScratchPostcardStatusButton(title: "다시 시도") { attempt += 1 }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .appStoreOverlay(isPresented: $showingFullAppOverlay) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
        .task(id: attempt) {
            #if DEBUG
            if let state = ScratchPostcardLoader.debugState { loader.show(state); return }
            #endif
            await loader.load(tag: tagID, repository: repository)
        }
    }
}

/// Figma "물음표 오이"(5400:4956): the question-mark cucumber over a centred green message, 16pt apart.
/// Used for the postcard's loading, unavailable and failed states.
struct ScratchPostcardStatusView<Action: View>: View {
    static var green: Color { Color(red: 112 / 255, green: 140 / 255, blue: 64 / 255) } // #708C40
    let message: String
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 16) {
            Image("ScratchPostcardQuestionOi")
                .resizable()
                .scaledToFit()
                .frame(width: 192, height: 300)
                .accessibilityHidden(true)
            Text(message)
                .font(.custom("Paperlogy-5Medium", size: 18))
                .tracking(0.36)
                .lineHeight(.exact(points: 27))
                .foregroundStyle(Self.green)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            action()
                .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// The green 46pt button of the postcard's action bar, reused on its status screens.
struct ScratchPostcardStatusButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.custom("Paperlogy-6SemiBold", size: 16))
                .foregroundStyle(.white)
                .padding(.horizontal, 32)
                .frame(minWidth: 180, minHeight: 46)
                .background(ScratchPostcardStatusView<EmptyView>.green, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
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

/// A face that is still downloading after the card became scratchable (#348).
struct ScratchPostcardPendingFace: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(ScratchPostcardFallbackFront.paper)
            ProgressView().scaleEffect(1.6)
        }
        .frame(width: 362, height: 502)
        .modifier(PostcardCanvas())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("엽서를 불러오는 중")
    }
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
