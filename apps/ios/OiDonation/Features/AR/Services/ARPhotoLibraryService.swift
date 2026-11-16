import Photos
import Foundation
import UIKit

struct ARPhotoLibraryService {
    enum Media { case photo, video }

    func save(_ url: URL, as media: Media) async throws {
        try await authorize()
        try await PHPhotoLibrary.shared().performChanges {
            switch media {
            case .photo: PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            case .video: PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        }
    }

    func save(_ image: UIImage) async throws {
        try await authorize()
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    func save(_ images: [UIImage]) async throws {
        guard !images.isEmpty else { return }
        let pngs = try images.map { image -> Data in
            guard let data = image.pngData() else {
                throw NSError(domain: "오이기부.PhotoLibrary", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "저장할 카드 이미지를 준비하지 못했어요."])
            }
            return data
        }
        try await authorize()
        try await PHPhotoLibrary.shared().performChanges {
            for data in pngs {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = "public.png"
                request.addResource(with: .photo, data: data, options: options)
            }
        }
    }

    private func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "오이기부.PhotoLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "사진 추가 권한이 없습니다. 설정에서 사진 추가를 허용해 주세요."])
        }
    }
}
