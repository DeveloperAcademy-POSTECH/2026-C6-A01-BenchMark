import Foundation

struct ARCaptureRecord: Codable {
    let date: Date
    let settings: ARCaptureSettings
    let operatingSystem: String
    let device: String
    let peopleOcclusionSupported: Bool
    let meshSupported: Bool
    let lightIntensity: Double?
    let colorTemperature: Double?
    let cameraTransform: [Float]
    let anchorTransform: [Float]
    let imageWidth: Int
    let imageHeight: Int
    let captureMethod: String
}
