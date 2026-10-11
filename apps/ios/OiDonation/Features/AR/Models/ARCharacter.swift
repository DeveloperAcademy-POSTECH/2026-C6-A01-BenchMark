import Foundation

enum ARCharacter: String, CaseIterable, Codable, Identifiable {
    case neopjuk, ponix, ponixVsNeopjuk, doni, neopjukAnimated
    var id: String { rawValue }
    var title: String {
        switch self {
        case .neopjuk: "넙죽이"
        case .ponix: "Ponix"
        case .ponixVsNeopjuk: "포닉스 vs 넙죽이"
        case .doni: "도니"
        case .neopjukAnimated: "넙죽이 · 애니메이션"
        }
    }
    var previewImageName: String { (self == .neopjukAnimated ? "neopjuk" : rawValue) + "Preview" }
    var modelFilename: String { rawValue + ".usdz" }
}
