//
//  OiCardImageExport.swift
//  OiDonation
//
//  Created by Codex on 11/13/26.
//

import SwiftUI
import UIKit

enum OiCardExportError: LocalizedError {
    case storyTooLong, imageUnavailable
    var errorDescription: String? {
        switch self {
        case .storyTooLong: "이야기를 한 장에 담기 어려워요. 문구를 줄인 뒤 다시 시도해 주세요."
        case .imageUnavailable: "카드 이미지를 준비하지 못했어요. 다시 시도해 주세요."
        }
    }
}

@MainActor enum OiCardImageExport {
    static func publication(front: UIImage, message: String, author: String, academicAuthor: String = "", cover: Data? = nil) throws -> OiStoryCardPublication {
        let style = OiPostcardBackgroundMetadata.style(for: front)
        let first = OiPostcardSnapshot.color(front, x: 0.05, y: 0.10) ?? 0xE8EECF
        let second = OiPostcardSnapshot.color(front, x: 0.95, y: 0.90) ?? 0xD5DBC6
        let back = try render(OiPostcardBack(first: first, second: second, backgroundStyle: style,
            message: message, author: OiPostcardAuthor.text(mode: style?.authorMode, name: author, academic: academicAuthor),
            exportFontSize: fittingFontSize(message)))
        let frontPNG = style.flatMap { OiPostcardBackgroundMetadata.png(image: front, style: $0) } ?? front.pngData()
        guard let frontPNG, let backPNG = back.pngData() else { throw OiCardExportError.imageUnavailable }
        return try OiStoryCardPublication(front: frontPNG, back: backPNG,
            frontPreview: preview(front), backPreview: preview(back), cover: cover)
    }

    static func render<Content: View>(_ content: Content, colorScheme: ColorScheme = .light) throws -> UIImage {
        let renderer = ImageRenderer(content: content.frame(width: 362, height: 502)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = 3
        guard let image = renderer.uiImage else { throw OiCardExportError.imageUnavailable }
        return image
    }

    /// Only the clean picture window leaves the device; decorations never enter this image.
    static func cover(_ cleanFront: UIImage) throws -> Data {
        guard let cg = cleanFront.cgImage,
              let crop = cg.cropping(to: CGRect(x: CGFloat(cg.width) * 33 / 362, y: CGFloat(cg.height) * 33 / 502,
                width: CGFloat(cg.width) * 296 / 362, height: CGFloat(cg.height) * 436 / 502).integral),
              let data = UIImage(cgImage: crop).pngData() else { throw OiCardExportError.imageUnavailable }
        return data
    }

    static func preview(_ image: UIImage) throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 724, height: 1004), format: format).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: 724, height: 1004))
        }
        guard let bytes = image.pngData() else { throw OiCardExportError.imageUnavailable }
        return bytes
    }

    // Export is a complete page, never a screenshot of the current scroll position.
    static func fittingFontSize(_ message: String) throws -> CGFloat {
        OiPostcardTypography.registerFonts()
        let text = message.isEmpty ? "아직 남긴 이야기가 없어요." : message
        for size in stride(from: CGFloat(17), through: 6, by: -0.5) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = OiPostcardTypography.lineSpacing * size / 17
            let bounds = (text as NSString).boundingRect(with: CGSize(width: 292, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [
                    .font: UIFont(name: OiPostcardTypography.handwritingName, size: size) ?? UIFont.systemFont(ofSize: size),
                    .kern: 0.17, .paragraphStyle: paragraph
                ], context: nil)
            if ceil(bounds.height) <= 385 { return size }
        }
        throw OiCardExportError.storyTooLong
    }
}

struct OiCardExportImages {
    let front: UIImage
    let back: UIImage?

    init(_ publication: OiStoryCardPublication) throws {
        guard let front = UIImage(data: publication.png) else { throw OiCardExportError.imageUnavailable }
        self.front = front
        if let data = publication.parts[.back] {
            guard let back = UIImage(data: data) else { throw OiCardExportError.imageUnavailable }
            self.back = back
        } else { back = nil }
    }

    init(front: UIImage, back: UIImage?) { self.front = front; self.back = back }
}

struct OiCardExportSheet: View {
    let load: () async throws -> OiCardExportImages
    @State private var images: OiCardExportImages?
    @State private var selection = Selection.both
    @State private var error: String?
    @State private var notice: String?
    @State private var working = false
    @State private var attempt = 0
    @State private var share: Share?
    @Environment(\.dismiss) private var dismiss

    enum Selection: String, CaseIterable { case front = "앞면", back = "뒷면", both = "앞·뒷면 모두" }
    private struct Share: Identifiable { let id = UUID(); let images: [UIImage] }
    private var selected: [UIImage] {
        guard let images else { return [] }
        switch selection {
        case .front: return [images.front]
        case .back: return images.back.map { [$0] } ?? []
        case .both: return [images.front] + (images.back.map { [$0] } ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let images {
                        Picker("저장할 면", selection: $selection) {
                            Text(Selection.front.rawValue).tag(Selection.front)
                            if images.back != nil {
                                Text(Selection.back.rawValue).tag(Selection.back)
                                Text(Selection.both.rawValue).tag(Selection.both)
                            }
                        }.pickerStyle(.segmented).disabled(working)
                        HStack {
                            ForEach(Array(selected.enumerated()), id: \.offset) { _, image in
                                Image(uiImage: image).resizable().scaledToFit()
                            }
                        }.frame(maxHeight: 350).accessibilityLabel("저장할 카드 미리보기")
                        if images.back == nil { Text("이전 버전 카드는 저장된 앞면만 제공해요.").font(.footnote) }
                        Button("사진첩에 저장", systemImage: "square.and.arrow.down") {
                            Task { await save() }
                        }.buttonStyle(.borderedProminent).disabled(working || selected.isEmpty)
                            .accessibilityIdentifier("oi.card.export.save")
                        Button("공유하기", systemImage: "square.and.arrow.up") {
                            share = Share(images: selected)
                        }.buttonStyle(.bordered).disabled(working || selected.isEmpty)
                            .accessibilityIdentifier("oi.card.export.share")
                    } else if error == nil { ProgressView("앞·뒷면을 준비하는 중") }
                    if working { ProgressView("사진첩에 저장하는 중") }
                    if let notice { Text(notice).foregroundStyle(.green).accessibilityIdentifier("oi.card.export.saved") }
                    if let error {
                        Text(error).foregroundStyle(.red)
                        if images == nil { Button("다시 시도") { attempt += 1 } }
                    }
                }.padding()
            }.navigationTitle("카드 저장·공유").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() }.disabled(working) } }
                .task(id: attempt) {
                    error = nil
                    do {
                        let loaded = try await load()
                        try Task.checkCancellation()
                        images = loaded
                        if loaded.back == nil { selection = .front }
                    } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
                }
                .sheet(item: $share) { value in OiCardShareSheet(images: value.images) }
        }.interactiveDismissDisabled(working)
    }

    private func save() async {
        guard !working else { return }
        let output = selected
        working = true; error = nil; notice = nil
        defer { working = false }
        do {
            try await ARPhotoLibraryService().save(output)
            notice = "카드 \(output.count)장을 사진첩에 저장했어요."
        } catch { self.error = error.localizedDescription }
    }
}

private struct OiCardShareSheet: UIViewControllerRepresentable {
    let images: [UIImage]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: images, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
