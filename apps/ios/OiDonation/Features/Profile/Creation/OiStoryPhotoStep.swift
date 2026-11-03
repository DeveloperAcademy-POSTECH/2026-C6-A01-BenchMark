import PhotosUI
import SwiftUI

struct OiStoryPhotoStep<Photo: View>: View {
    let items: [OiEditingPhoto]
    let uploadedPhotos: Set<UUID>
    @Binding var selections: [PhotosPickerItem]
    let loadPhoto: (UUID) async throws -> Data
    let edit: (UUID, OiPhotoEdit) -> Void
    let remove: (OiEditingPhoto) -> Void
    let photo: (OiEditingPhoto) -> Photo
    @State private var selected: OiEditingPhoto?
    @State private var cropPhotoID: UUID?
    @State private var cropRequest: CropRequest?
    @State private var cropError: String?
    @State private var editedIndex: Int?
    private struct CropRequest: Identifiable {
        let id: UUID
        let image: UIImage
    }
    private var current: OiEditingPhoto? { selected.flatMap { items.contains($0) ? $0 : nil } ?? items.first }
    var body: some View {
        VStack(spacing: 22) {
            if let current {
                photo(current).frame(maxWidth: 350).frame(height: 400)
                HStack(spacing: 9) {
                    Button {
                        if case .local(let id) = current { cropPhotoID = id }
                    } label: { toolLabel("자르기", symbol: "crop") }
                        .buttonStyle(.plain).disabled(!canEdit).accessibilityIdentifier("oi.photos.crop")
                    editButton("회전", symbol: "rotate.left", operation: .rotateLeft)
                    Button { remove(current); selected = nil } label: { toolLabel("삭제", symbol: "trash") }
                        .buttonStyle(.plain)
                }
                if !canEdit { Text("업로드된 사진은 삭제 후 새 사진으로 바꿀 수 있어요.").font(.caption).foregroundStyle(.secondary) }
            } else {
                ContentUnavailableView("이야기에 담을 사진을 골라주세요", systemImage: "photo.on.rectangle.angled", description: Text("선택한 사진은 먼저 이 기기에 보관돼요."))
                    .frame(minHeight: 290)
            }
            Text("\(items.count)장 선택").font(CampusStyle.semibold(12))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .foregroundStyle(Color(white: 0.14)).background(Color(white: 0.65), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { selected = item } label: {
                            VStack(spacing: 6) {
                                photo(item).frame(width: 60, height: 76).clipped()
                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(current == item ? .white : .clear, lineWidth: 2) }
                                    .shadow(color: current == item ? .white.opacity(0.6) : .clear, radius: 4)
                                Text("\(index + 1)").font(.caption)
                            }
                        }.buttonStyle(.plain).accessibilityLabel("\(index + 1)번째 사진 선택")
                    }
                    PhotosPicker(selection: $selections, matching: .images) {
                        VStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 30))
                                .frame(width: 60, height: 76)
                                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            Text("추가").font(.caption)
                        }
                    }.accessibilityIdentifier("oi.photos.add").buttonStyle(.plain)
                }.padding(4)
            }
        }
        .disabled(cropPhotoID != nil)
        .overlay { if cropPhotoID != nil { ProgressView("사진 준비 중") } }
        .task(id: cropPhotoID) {
            guard let id = cropPhotoID else { return }
            defer { cropPhotoID = nil }
            do {
                let data = try await loadPhoto(id)
                try Task.checkCancellation()
                guard items.contains(.local(id)), let image = UIImage(data: data) else { throw OiServiceError.invalidInput }
                cropRequest = CropRequest(id: id, image: image)
            } catch is CancellationError { }
            catch { cropError = "사진을 열지 못했어요. 다시 시도해 주세요." }
        }
        .fullScreenCover(item: $cropRequest) { request in
            OiPhotoCropEditor(image: request.image) { rect in
                editedIndex = items.firstIndex(of: .local(request.id))
                edit(request.id, .crop(rect))
            }
        }
        .alert("사진 자르기", isPresented: Binding(get: { cropError != nil }, set: { if !$0 { cropError = nil } })) {
            Button("확인") { cropError = nil }
        } message: { Text(cropError ?? "") }
        .onChange(of: items) { _, newItems in
            if let index = editedIndex, newItems.indices.contains(index) { selected = newItems[index] }
            editedIndex = nil
        }
    }
    private var canEdit: Bool {
        if case .local(let id) = current { return !uploadedPhotos.contains(id) }
        return false
    }
    private func editButton(_ title: String, symbol: String, operation: OiPhotoEdit) -> some View {
        Button {
            if case .local(let id) = current {
                editedIndex = items.firstIndex(of: .local(id)); edit(id, operation)
            }
        } label: {
            toolLabel(title, symbol: symbol)
        }.buttonStyle(.plain).disabled(!canEdit)
    }
    private func toolLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22))
            Text(title).font(.custom("Paperlogy-5Medium", size: 20, relativeTo: .body))
        }.frame(maxWidth: 86, minHeight: 88)
            .foregroundStyle(Color("OiGreen"))
            .background(Color("OiLight"), in: RoundedRectangle(cornerRadius: 20))
    }
}

enum OiPhotoEdit { case rotateLeft, crop(CGRect) }
