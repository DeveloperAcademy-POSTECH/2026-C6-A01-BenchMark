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

    private func authorize() async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "오이기부.PhotoLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "사진 추가 권한이 없습니다. 설정에서 허용하거나 공유 버튼으로 내보내세요."])
        }
    }
}
