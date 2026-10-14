import ARKit
import RealityKit
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

@MainActor
final class ARPhotoCaptureService {
    func capture(view: RealityKit.ARView, viewport: CGRect, frame: ARFrame, anchor: AnchorEntity?, settings: ARCaptureSettings,
                 peopleSupported: Bool, meshSupported: Bool,
                 snapshot: ((@escaping (UIImage?) -> Void) -> Void)? = nil, completion: @escaping (Result<ARCaptureResult, Error>) -> Void) {
        let visibleRect = view.convert(viewport, from: view.window).intersection(view.bounds)
        let bounds = view.bounds
        let capturedSettings = settings
        let cameraMatrix = frame.camera.transform
        let anchorMatrix = anchor?.transformMatrix(relativeTo: nil)
        let intensity = frame.lightEstimate.map { Double($0.ambientIntensity) }
        let temperature = frame.lightEstimate.map { Double($0.ambientColorTemperature) }
        let date = Date()
        let receiveImage: (UIImage?) -> Void = { image in
            guard let image, let image = Self.process(image, rect: visibleRect, bounds: bounds, settings: capturedSettings),
                  let data = image.jpegData(compressionQuality: 0.95) else {
                completion(.failure(NSError(domain: "오이기부.Photo", code: 1, userInfo: [NSLocalizedDescriptionKey: "사진을 생성하지 못했습니다. 다시 촬영해 주세요."])))
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
                    cameraTransform: Self.flatten(cameraMatrix), anchorTransform: anchorMatrix.map(Self.flatten) ?? [],
                    imageWidth: image.cgImage?.width ?? 0, imageHeight: image.cgImage?.height ?? 0,
                    captureMethod: capturedSettings.background == .stadium
                        ? "RealityKit postprocess output; metadata sampled before next composited frame, not frame-synchronized"
                        : "RealityKit.ARView.snapshot; metadata sampled immediately before snapshot, not frame-synchronized")
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try data.write(to: imageURL, options: .atomic)
                try encoder.encode(record).write(to: metadataURL, options: .atomic)
                completion(.success(ARCaptureResult(image: image, imageURL: imageURL, metadataURL: metadataURL)))
            } catch { completion(.failure(error)) }
        }
        if let snapshot { snapshot(receiveImage) }
        else { view.snapshot(saveToHDR: false, completion: receiveImage) }
    }


    // Crop the full-screen AR snapshot to the visible photo window.
    private static func process(_ image: UIImage, rect: CGRect, bounds: CGRect, settings: ARCaptureSettings) -> UIImage? {
        guard let source = image.cgImage, bounds.width > 0, bounds.height > 0, !rect.isEmpty else { return nil }
        let pixels = CGRect(x: rect.minX / bounds.width * CGFloat(source.width),
                            y: rect.minY / bounds.height * CGFloat(source.height),
                            width: rect.width / bounds.width * CGFloat(source.width),
                            height: rect.height / bounds.height * CGFloat(source.height)).integral
        guard let cropped = source.cropping(to: pixels) else { return nil }
        let image = UIImage(cgImage: cropped)
        guard settings.photoFilter != .original else { return image }
        let input = CIImage(cgImage: cropped)
        let filter = CIFilter.colorControls()
        filter.inputImage = input
        filter.saturation = Float(settings.photoFilter.saturation)
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    private static func flatten(_ matrix: simd_float4x4) -> [Float] {
        (0..<4).flatMap { column in (0..<4).map { matrix[column][$0] } }
    }
}
