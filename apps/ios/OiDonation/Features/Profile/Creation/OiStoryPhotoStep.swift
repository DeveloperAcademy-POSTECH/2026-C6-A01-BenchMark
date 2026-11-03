import PhotosUI
import SwiftUI

struct OiStoryPhotoStep<Photo: View>: View {
    let items: [OiEditingPhoto]
    let uploadedPhotos: Set<UUID>
    @Binding var selections: [PhotosPickerItem]
    let edit: (UUID, OiPhotoEdit) -> Void
    let remove: (OiEditingPhoto) -> Void
    let photo: (OiEditingPhoto) -> Photo
    @State private var selected: OiEditingPhoto?
    private var current: OiEditingPhoto? { selected.flatMap { items.contains($0) ? $0 : nil } ?? items.first }
    var body: some View {
        VStack(spacing: 22) {
            if let current {
                photo(current).frame(maxWidth: .infinity).frame(height: 310)
                HStack(spacing: 14) {
                    editButton("가운데 자르기", symbol: "crop", operation: .squareCrop)
                    editButton("회전", symbol: "rotate.left", operation: .rotateLeft)
                    Button { remove(current); selected = nil } label: { toolLabel("삭제", symbol: "trash") }
                        .buttonStyle(.plain)
                }
                if !canEdit { Text("업로드된 사진은 삭제 후 새 사진으로 바꿀 수 있어요.").font(.caption).foregroundStyle(.secondary) }
            } else {
                ContentUnavailableView("이야기에 담을 사진을 골라주세요", systemImage: "photo.on.rectangle.angled", description: Text("선택한 사진은 먼저 이 기기에 보관돼요."))
                    .frame(minHeight: 290)
            }
            HStack {
                Text("\(items.count)장 선택").font(.caption)
                Spacer()
                PhotosPicker(selection: $selections, matching: .images) {
                    Label("사진 추가", systemImage: "plus").padding(.horizontal, 14).padding(.vertical, 10)
                        .foregroundStyle(Color("OiGreen")).background(Color("OiLight"), in: Capsule())
                }.accessibilityIdentifier("oi.photos.add").buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { selected = item } label: {
                            VStack(spacing: 6) {
                                photo(item).frame(width: 64, height: 80).clipped()
                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(current == item ? Color("OiGreen") : .clear, lineWidth: 3) }
                                Text("\(index + 1)").font(.caption)
                            }
                        }.buttonStyle(.plain).accessibilityLabel("\(index + 1)번째 사진 선택")
                    }
                }.padding(4)
            }
        }
    }
    private var canEdit: Bool {
        if case .local(let id) = current { return !uploadedPhotos.contains(id) }
        return false
    }
    private func editButton(_ title: String, symbol: String, operation: OiPhotoEdit) -> some View {
        Button { if case .local(let id) = current { edit(id, operation) } } label: {
            toolLabel(title, symbol: symbol)
        }.buttonStyle(.plain).disabled(!canEdit)
    }
    private func toolLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22))
            Text(title).font(.custom("Paperlogy-5Medium", size: 14, relativeTo: .caption))
        }.frame(maxWidth: .infinity, minHeight: 80)
            .foregroundStyle(Color("OiGreen"))
            .background(Color("OiLight"), in: RoundedRectangle(cornerRadius: 20))
    }
}

enum OiPhotoEdit { case rotateLeft, squareCrop }
