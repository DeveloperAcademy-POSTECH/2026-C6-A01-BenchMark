import SwiftUI

struct ARCharacterThumbnail: View {
    let character: ARCharacter
    var size: CGFloat = 52

    var body: some View {
        Image(character.previewImageName)
            .resizable()
            .scaledToFit()
            .padding(4)
            .frame(width: size, height: size)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

