import AVFoundation

@MainActor
final class ARVideoExporter {
    private var activeExporter: AVAssetExportSession?
    func cancel() { activeExporter?.cancelExport() }

    func exportCameraArea(from url: URL, crop: CGRect) async throws -> URL {
        defer { activeExporter = nil }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw failure("녹화된 영상 프레임이 없습니다.")
        }
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else {
            throw failure("마이크 음성 트랙이 기록되지 않았습니다. 마이크 접근을 허용하고 다시 촬영해 주세요.")
        }
        let natural = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        guard duration.seconds > 0 else { throw failure("녹화 시간이 너무 짧습니다.") }
        guard let geometry = ARVideoCropGeometry(naturalSize: natural, preferredTransform: preferred, normalizedRect: crop) else {
            throw failure("촬영 영역이 올바르지 않습니다.")
        }
        let composition = AVMutableVideoComposition()
        composition.renderSize = geometry.size
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(geometry.transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw failure("영상 내보내기를 준비하지 못했습니다.")
        }
        activeExporter = exporter
        exporter.videoComposition = composition
        let directory = URL.documentsDirectory.appending(path: "Videos")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appending(path: "\(UUID().uuidString).mp4")
        do {
            try await exporter.export(to: destination, as: .mp4)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "오이기부.Video", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
