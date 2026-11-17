import Foundation

enum ARCharacter: String, CaseIterable, Codable, Identifiable {
    case neopjuk, ponix, ponixVsNeopjuk, doni, neopjukAnimated
    case oiDinosaur, oiCat, oiBaseball, oiFarmer, oiSportswear
    /// Retain old raw values for saved photo records, separately from offered choices.
    static let selectableCases: [ARCharacter] = [.ponix, .neopjuk, .ponixVsNeopjuk,
        .oiDinosaur, .oiCat, .oiBaseball, .oiFarmer, .oiSportswear]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .neopjuk: "넙죽이"
        case .ponix: "포닉스"
        case .ponixVsNeopjuk: "포닉스 vs 넙죽이"
        case .doni: "도니"
        case .neopjukAnimated: "넙죽이 · 애니메이션"
        case .oiDinosaur: "공룡 잠옷 오이"
        case .oiCat: "고양이 잠옷 오이"
        case .oiBaseball: "야구복 오이"
        case .oiFarmer: "농부 오이"
        case .oiSportswear: "운동복 오이"
        }
    }
    var wardrobeCostumeID: String? {
        switch self {
        case .oiDinosaur: "dinosaur"
        case .oiCat: "cat"
        case .oiBaseball: "baseball"
        case .oiFarmer: "farmer"
        case .oiSportswear: "sportswear"
        default: nil
        }
    }
    var previewImageName: String {
        if let wardrobeCostumeID { return "ar-costume-" + wardrobeCostumeID }
        return (self == .neopjukAnimated ? "neopjuk" : rawValue) + "Preview"
    }
    var modelFilename: String {
        if let wardrobeCostumeID { return "wardrobe-costume-" + wardrobeCostumeID + ".usdz" }
        return rawValue + ".usdz"
    }
}
