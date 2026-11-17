import Foundation

struct ARCaptureSettings: Codable, Equatable {
    var background: ARCameraBackground = .original
    var photoRatio: ARPhotoRatio = .standard
    var photoTimer = 0
    var opaquePhotoMargins = false
    var cameraExposure: Float = 0
    var photoFilter: ARPhotoFilter = .original
    var character: ARCharacter = .ponix
    // Optional fields preserve decoding of photo records made before palm placement.
    var placementMode: ARManualPlacementMode? = .palm
    var palmHeight: Float? = nil
    var palmRotation: Float? = nil
    // Optional so older capture records remain readable.
    var palmResponse: ARPalmResponse? = nil
    /// Present only for a selected public cucumber; legacy mascot records still decode.
    var cucumberStoryID: UUID? = nil
    var cucumberName: String? = nil
    var height: Float = 1.2
    var rotation: Float = 0
    var floorOffset: Float = 0
    var environmentLight = true
    var exposure: Float = 0
    var groundingShadow = true
    var peopleOcclusion = true
    var sceneOcclusion = false
    var directLight = true
    var azimuth: Float = 45
    var elevation: Float = 45
    var intensity: Float = 850
}

enum ARPalmResponse: String, Codable, CaseIterable {
    case responsive, stable
    var title: String { self == .responsive ? "빠른 추적" : "안정 추적" }
}

enum ARManualPlacementMode: String, Codable, CaseIterable {
    case floor, palm, location
    var title: String {
        switch self { case .floor: "바닥 인식"; case .palm: "손바닥 인식"; case .location: "위치 인식" }
    }
    var symbol: String {
        switch self { case .floor: "square.dashed"; case .palm: "hand.raised.fill"; case .location: "mappin.and.ellipse" }
    }
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

// Retain the retired stadium value so existing photo metadata remains decodable.
enum ARCameraBackground: String, Codable, CaseIterable {
    case original = "원본", stadium = "경기장"
}
