import UIKit

struct ARCaptureResult: Identifiable {
    let id = UUID()
    let image: UIImage
    let imageURL: URL
    let metadataURL: URL
}
