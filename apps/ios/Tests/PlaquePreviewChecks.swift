import CoreGraphics
import Foundation
import ImageIO

@main
struct PlaquePreviewChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ text: String) { precondition(condition(), text) }
    static func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }
    static func save(_ image: CGImage, path: String) {
        let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        require(CGImageDestinationFinalize(destination), "write test proof")
    }
    static func main() async throws {
        let valid = PlaquePhotoPlacement.centered
        require(valid.isValid, "Valid rectangle")
        var bad = valid
        bad.topLeft.x = .nan
        require(!bad.isValid, "Reject NaN")
        bad = valid; bad.bottomRight = valid.topLeft
        require(!bad.isValid, "Reject collapsed or crossed corners")
        bad = valid; bad.topRight.x = 1.1
        require(!bad.isValid, "Reject outside photo")
        bad = valid; bad.bottomLeft = valid.topRight; bad.topRight = valid.bottomLeft
        require(!bad.isValid, "Reject self-intersection")
        let json = try JSONEncoder().encode(valid)
        let decoded = try JSONDecoder().decode(PlaquePhotoPlacement.self, from: json)
        require(decoded == valid, "Placement roundtrip")
        let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil)!
        let photo = CGImageSourceCreateImageAtIndex(source, 0, nil)!.cropping(to: CGRect(x: 130, y: 690, width: 490, height: 330))!
        let placement = PlaquePhotoPlacement(topLeft: .init(x: 0.57, y: 0.15), topRight: .init(x: 0.74, y: 0.175),
            bottomRight: .init(x: 0.74, y: 0.25), bottomLeft: .init(x: 0.57, y: 0.225))
        let renderer = PlaquePreviewRenderer()
        let fixtureData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let loaded = try await renderer.loadPhoto(data: fixtureData)
        require(loaded.width > 0 && loaded.height > 0 && max(loaded.width, loaded.height) <= 2048, "Bound imported photo size")
        do {
            _ = try await renderer.loadPhoto(data: Data("invalid image".utf8))
            preconditionFailure("Invalid image accepted")
        } catch PlaquePreviewError.imageUnavailable { }
        let first = try await renderer.render(message: "꿈꾸는 후배들을 응원합니다.", photo: photo, placement: placement)
        let second = try await renderer.render(message: "졸업 10주년을 기념하며\n다시 만날 우리에게", photo: photo, placement: placement)
        require(!first.usesPlaceholder && first.message == "꿈꾸는 후배들을 응원합니다.", "Exact Hangul message")
        require(second.message.contains("\n"), "Preserve line breaks")
        require(pixels(first.plaque) != pixels(second.plaque), "Changing text updates close-up")
        require(pixels(first.bench) != pixels(second.bench), "Changing text updates composite")
        require(first.bench.width == photo.width && first.bench.height == photo.height, "Keep photo dimensions")
        let original = pixels(photo), composed = pixels(first.bench)
        // Outside the small plaque region, the photo must remain untouched.
        for index in [0, photo.width - 1, photo.width * (photo.height - 1)] {
            for channel in 0..<3 {
                require(abs(Int(original[index * 4 + channel]) - Int(composed[index * 4 + channel])) <= 2, "Preserve bench photograph")
            }
        }
        let empty = try await renderer.render(message: " \n", photo: photo, placement: placement)
        require(empty.usesPlaceholder && empty.message.isEmpty, "Placeholder is not a donor message")
        do {
            _ = try await renderer.render(message: String(repeating: "기념 ", count: 600), photo: photo, placement: placement)
            preconditionFailure("Long message was silently clipped")
        } catch PlaquePreviewError.messageTooLong { }
        do {
            _ = try await renderer.render(message: "문구", photo: photo, placement: bad)
            preconditionFailure("Invalid placement accepted")
        } catch PlaquePreviewError.invalidPlacement { }
        let cancelled = Task { try await renderer.render(message: "취소", photo: photo, placement: placement) }
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Cancelled rendering published") }
        catch is CancellationError { }
        save(second.plaque, path: "/tmp/oi-plaque-closeup-proof.png")
        save(second.bench, path: "/tmp/oi-plaque-bench-proof.png")
        print("PASS: placement validation, exact Hangul/newlines, synchronized previews, original photo preservation, empty/long text and cancellation")
    }
}
