import Foundation

struct ARCaptureSettings: Codable, Equatable {
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
