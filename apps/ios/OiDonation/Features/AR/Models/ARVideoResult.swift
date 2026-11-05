import Foundation

struct ARVideoResult: Identifiable {
    enum Kind { case cropped, recoveryOriginal }
    let id = UUID()
    let url: URL
    var kind: Kind = .cropped
}
