import SwiftUI
import ImageIO

struct ClipRemoteImage: View {
    let asset: ClipAsset
    let client: ClipContentClient
    @State private var image: UIImage?
    @State private var failed = false
    @State private var retry = UUID()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("이야기 사진")
            } else if failed {
                Button("사진 다시 불러오기", systemImage: "arrow.clockwise") { retry = UUID() }
            } else { ProgressView("사진을 불러오는 중이에요") }
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .task(id: asset.url.absoluteString + (asset.sha256 ?? "") + retry.uuidString) {
            image = nil; failed = false
            do {
                let file = try await client.asset(asset, model: false)
                try Task.checkCancellation()
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1600,
                        kCGImageSourceCreateThumbnailWithTransform: true
                      ] as CFDictionary) else { throw ClipError.invalidResponse }
                image = UIImage(cgImage: thumbnail)
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}
