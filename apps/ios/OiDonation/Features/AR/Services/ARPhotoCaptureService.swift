import ARKit
import RealityKit
import UIKit

@MainActor
final class ARPhotoCaptureService {
    func capture(view: RealityKit.ARView, frame: ARFrame, anchor: AnchorEntity, settings: ARCaptureSettings,
                 peopleSupported: Bool, meshSupported: Bool, completion: @escaping (Result<ARCaptureResult, Error>) -> Void) {
        let capturedSettings = settings
        let cameraMatrix = frame.camera.transform
        let anchorMatrix = anchor.transformMatrix(relativeTo: nil)
        let intensity = frame.lightEstimate.map { Double($0.ambientIntensity) }
        let temperature = frame.lightEstimate.map { Double($0.ambientColorTemperature) }
        let date = Date()
        view.snapshot(saveToHDR: false) { image in
            guard let image, let data = image.jpegData(compressionQuality: 0.95) else {
                completion(.failure(NSError(domain: "OiDonation.Photo", code: 1, userInfo: [NSLocalizedDescriptionKey: "사진을 생성하지 못했습니다. 다시 촬영해 주세요."])))
                return
            }
            do {
                let directory = URL.documentsDirectory.appending(path: "Experiments/\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let imageURL = directory.appending(path: "photo.jpg")
                let metadataURL = directory.appending(path: "settings.json")
                let record = ARCaptureRecord(date: date, settings: capturedSettings,
                    operatingSystem: UIDevice.current.systemVersion, device: UIDevice.current.model,
                    peopleOcclusionSupported: peopleSupported, meshSupported: meshSupported,
                    lightIntensity: intensity, colorTemperature: temperature,
                    cameraTransform: Self.flatten(cameraMatrix), anchorTransform: Self.flatten(anchorMatrix),
                    imageWidth: image.cgImage?.width ?? 0, imageHeight: image.cgImage?.height ?? 0,
                    captureMethod: "RealityKit.ARView.snapshot; metadata sampled immediately before snapshot, not frame-synchronized")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try data.write(to: imageURL, options: .atomic)
                try encoder.encode(record).write(to: metadataURL, options: .atomic)
                completion(.success(ARCaptureResult(image: image, imageURL: imageURL, metadataURL: metadataURL)))
            } catch { completion(.failure(error)) }
        }
    }


    private static func flatten(_ matrix: simd_float4x4) -> [Float] {
        (0..<4).flatMap { column in (0..<4).map { matrix[column][$0] } }
    }
}
