import Foundation

/// Colors sampled from the original Figma swatch vectors (4597:4930).
enum OiCardPalette {
    struct Swatch: Identifiable {
        let name: String
        let first: UInt32
        let second: UInt32
        var id: String { name }
    }
    static func items(gradient: Bool, border: Bool) -> [Swatch] {
        let names = gradient ? ["샌드", "선셋", "오렌지", "멜론", "라임", "그린티", "지구", "스카이", "미드나잇", "오키드", "블러시", "아이언"]
            : ["화이트", "아이보리", "오트밀", "토프", "스톤", "차콜", "세이지", "민트", "스카이", "라벤더", "블러시", "버터"]
        let first: [UInt32]
        let second: [UInt32]
        if gradient && border {
            first = [0xF9F2E5,0xFFE0D2,0xFFE4C5,0xFFFAE8,0xFFFBCB,0xEDFAD8,0xE3FAEF,0xE0FAF3,0xDDF5FA,0xEEE3FF,0xFFF1E8,0xFAF7F0]
            second = [0xF7E8CF,0xFFF7BF,0xFFFACB,0xECF8DE,0xEAF8D8,0xDDF6EE,0xE6F3FF,0xDEEAFE,0xEEE3FC,0xFFE0EF,0xFFE2EC,0xE4E7EB]
        } else if gradient {
            first = [0xF0DFC4,0xD95359,0xEC9045,0xF0E2B0,0xDADD58,0x97DD77,0x98D3C0,0x97DADD,0x74BCD4,0xA27FCE,0xEDCBD1,0xC9C9C9]
            second = [0xD1B381,0xDAB642,0xEBD035,0xBCD59D,0x90C151,0x6CB59A,0xA5CCE9,0x5184C3,0x7160AE,0xB867A5,0xFF879D,0x5C5C5C]
        } else {
            first = border ? [0xFFFFFF,0xFFFDFA,0xF7F0E4,0xF3E9E5,0xE9EFEC,0xD1D1D1,0xF3FDF0,0xF4FDFA,0xF2F8FC,0xF3EFFA,0xFCEEF0,0xF9F5EA]
                : [0xFFFFFF,0xF4EBDD,0xD8CBB6,0xB6A097,0xB7BEBA,0x575958,0xC7D8C1,0xC2DDD4,0xC5DBEC,0xD6CCE6,0xEDCBD1,0xF0E2B0]
            second = first
        }
        let basic = names.indices.map { Swatch(name: names[$0], first: first[$0], second: second[$0]) }
        guard border else { return basic }
        let papers: [Swatch] = [
            .init(name: "엽서 그린", first: 0xE8EECF, second: gradient ? 0xD5DBC6 : 0xE8EECF),
            .init(name: "엽서 라일락", first: 0xE8D8E8, second: gradient ? 0xC5B3CC : 0xE8D8E8),
            .init(name: "엽서 로즈", first: 0xF1D8D6, second: gradient ? 0xD5B9B4 : 0xF1D8D6)
        ]
        return papers + basic
    }
}
