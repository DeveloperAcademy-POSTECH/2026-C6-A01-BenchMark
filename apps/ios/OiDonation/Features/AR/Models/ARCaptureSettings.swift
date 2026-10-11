import Foundation

struct ARCaptureSettings: Codable, Equatable {
    var photoRatio: ARPhotoRatio = .standard
    var photoTimer = 0
    var opaquePhotoMargins = false
    var cameraExposure: Float = 0
    var photoFilter: ARPhotoFilter = .original
    var character: ARCharacter = .neopjuk
    var height: Float = 1.2
    var rotation: Float = 0
    var floorOffset: Float = 0
    var environmentLight = true
    var exposure: Float = 0
    var groundingShadow = true
    var peopleOcclusion = true
    var sceneOcclusion = false
    var directLight = false
    var azimuth: Float = 45
    var elevation: Float = 45
    var intensity: Float = 1500
}

enum ARPhotoRatio: String, Codable, CaseIterable {
    case standard = "4:3", square = "1:1", wide = "16:9"
    var portraitRatio: CGFloat {
        switch self { case .standard: 3.0 / 4; case .square: 1; case .wide: 9.0 / 16 }
    }
}

enum ARPhotoFilter: String, Codable, CaseIterable {
    case original = "원본", vivid = "선명", muted = "차분", mono = "흑백"
    var saturation: Double {
        switch self { case .original: 1; case .vivid: 1.5; case .muted: 0.5; case .mono: 0 }
    }
}
