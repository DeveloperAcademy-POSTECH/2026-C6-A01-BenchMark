import Foundation

struct User: Identifiable, Sendable {
    let id: UUID
    let displayName: String
}

struct Reaction: Identifiable, Sendable {
    let id: UUID
    let plaqueID: String
    let kind: Kind
    enum Kind: Sendable {
        case appreciation
        case message(String)
    }
}
