import SwiftUI

struct ARCharacterSelectionView: View {
    @Binding var selection: ARCharacter
    var originalSubject: ARCameraSubject? = nil
    var isMascotSelected = true
    var restoreOriginal: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("캐릭터 선택").font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel("캐릭터 목록 닫기")
            }
            if let originalSubject, let restoreOriginal {
                Button {
                    restoreOriginal()
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ARSelectedCharacterThumbnail(character: selection, subject: originalSubject, size: 52)
                        Text(originalSubject.title).font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        if !isMascotSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(!isMascotSelected ? Color.mint.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("캠퍼스에서 선택한 오이: " + originalSubject.title)
                .accessibilityAddTraits(isMascotSelected ? [] : .isSelected)
                .accessibilityIdentifier("ar.camera.restoreStory")
                Divider()
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(ARCharacter.selectableCases) { character in
                        Button {
                            selection = character
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                ARCharacterThumbnail(character: character)
                                Text(character.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 4)
                                if isMascotSelected && character == selection {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(isMascotSelected && character == selection ? Color.mint.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(character.title)
                        .accessibilityAddTraits(isMascotSelected && character == selection ? .isSelected : [])
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(16)
        .frame(idealWidth: 320, maxWidth: 360)
        .tint(.mint)
    }
}
