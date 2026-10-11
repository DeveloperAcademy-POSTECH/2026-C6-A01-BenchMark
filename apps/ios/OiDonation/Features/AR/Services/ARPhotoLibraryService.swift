import Photos
import Foundation

struct ARPhotoLibraryService {
    enum Media { case photo, video }

    func save(_ url: URL, as media: Media) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw NSError(domain: "OiDonation.PhotoLibrary", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "사진 추가 권한이 없습니다. 설정에서 허용하거나 공유 버튼으로 내보내세요."])
        }
        try await PHPhotoLibrary.shared().performChanges {
            switch media {
            case .photo: PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            case .video: PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        }
    }
}
