import PhotosUI
import SwiftUI
import UIKit

struct OiStoryPhotoStep<Photo: View>: View {
    let items: [OiEditingPhoto]
    let uploadedPhotos: Set<UUID>
    @Binding var selections: [PhotosPickerItem]
    let loadPhoto: (UUID) async throws -> Data
    let edit: (UUID, OiPhotoEdit) async -> Bool
    let remove: (OiEditingPhoto) -> Void
    let photo: (OiEditingPhoto) -> Photo
    var thumbnail: ((OiEditingPhoto) -> Photo)? = nil
    var previewHeight: CGFloat = 400
    @State private var previewImage: UIImage?
    @State private var previewID: UUID?
    @State private var isEditing = false
    @State private var resetRotation = UUID()
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
        VStack(spacing: 0) {
            if let current {
                Group {
                    if case .local(let id) = current, canEdit, previewID == id, let previewImage {
                        OiRotatablePhoto(image: previewImage, resetToken: resetRotation) { radians in
                            Task { await applyEdit(id, operation: .rotate(radians)) }
                        }
                        .id(id)
                        .accessibilityLabel("선택한 사진")
                        .accessibilityHint("두 손가락으로 돌리면 사진이 회전해요. 빈 모서리가 생기지 않도록 확대되어 저장돼요.")
                        .accessibilityIdentifier("oi.photos.rotationPreview")
                    } else { photo(current) }
                }
                .frame(maxWidth: 350).frame(height: previewHeight).padding(.bottom, 30)
                HStack(spacing: 9) {
                    Button {
                        if case .local(let id) = current { cropPhotoID = id }
                    } label: { toolLabel("자르기", symbol: "crop") }
                        .buttonStyle(.plain).disabled(!canEdit).accessibilityIdentifier("oi.photos.crop")
                    editButton("회전", symbol: "rotate.left", operation: .rotateLeft)
                    Button { remove(current); selected = nil } label: { toolLabel("삭제", symbol: "trash") }
                        .buttonStyle(.plain).accessibilityIdentifier("oi.photos.delete")
                }.padding(.bottom, canEdit ? 30 : 0)
                if !canEdit {
                    Text("업로드된 사진은 삭제 후 새 사진으로 바꿀 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.vertical, 15)
                }
            } else {
                ContentUnavailableView("이야기에 담을 사진을 골라주세요", systemImage: "photo.on.rectangle.angled", description: Text("선택한 사진은 먼저 이 기기에 보관돼요."))
                    .frame(minHeight: previewHeight).padding(.bottom, 22)
            }
            Text("\(items.count)장 선택")
                .font(.custom("Paperlogy-6SemiBold", size: 12, relativeTo: .caption))
                .tracking(0.24)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .foregroundStyle(.black)
                .background(Color(red: 241 / 255, green: 244 / 255, blue: 236 / 255).opacity(0.6), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button { selected = item } label: {
                            VStack(spacing: 10) {
                                (thumbnail?(item) ?? photo(item)).frame(width: 60, height: 75).clipped()
                                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(current == item ? .white : .clear, lineWidth: 3) }
                                    .shadow(color: current == item ? .white.opacity(0.6) : .clear, radius: 8)
                                    .overlay(alignment: .top) {
                                        if index == 0 {
                                            Text("대표").font(CampusStyle.medium(10))
                                                .foregroundStyle(.black).padding(.horizontal, 10).padding(.vertical, 2)
                                                .background(.white, in: Capsule()).padding(.top, 6)
                                        }
                                    }
                                thumbnailLabel("\(index + 1)")
                            }
                        }.buttonStyle(.plain).accessibilityLabel("\(index + 1)번째 사진 선택")
                            .accessibilityAddTraits(current == item ? .isSelected : [])
                    }
                    PhotosPicker(selection: $selections, matching: .images) {
                        VStack(spacing: 10) {
                            Image(systemName: "plus").font(.system(size: 30))
                                .frame(width: 60, height: 75)
                                .foregroundStyle(Color("OiDark"))
                                .background(Color("OiBorder"), in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityHidden(true)
                            thumbnailLabel("추가")
                        }
                    }.accessibilityIdentifier("oi.photos.add").buttonStyle(.plain)
                }.padding(.vertical, 4)
            }.padding(.top, current == nil ? 18 : 14)
        }
        .disabled(cropPhotoID != nil || isEditing)
        .task(id: current) {
            previewImage = nil; previewID = nil
            guard case .local(let id) = current, !uploadedPhotos.contains(id) else { return }
            do {
                let bytes = try await loadPhoto(id)
                try Task.checkCancellation()
                guard current == .local(id), let image = UIImage(data: bytes) else { return }
                previewImage = image; previewID = id
            } catch is CancellationError { }
            catch { cropError = "사진을 열지 못했어요. 다른 사진을 선택한 뒤 다시 시도해 주세요." }
        }
        .overlay { if cropPhotoID != nil { ProgressView().accessibilityLabel("사진 준비 중") } }
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
                Task { await applyEdit(request.id, operation: .crop(rect)) }
            }
        }
        .alert("사진 편집", isPresented: Binding(get: { cropError != nil }, set: { if !$0 { cropError = nil } })) {
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
                Task { await applyEdit(id, operation: operation) }
            }
        } label: {
            toolLabel(title, symbol: symbol)
        }.buttonStyle(.plain).disabled(!canEdit).accessibilityIdentifier("oi.photos.rotate")
            .accessibilityHint("왼쪽으로 90도 회전. 사진 위에서 두 손가락으로 원하는 각도로 돌릴 수도 있어요.")
    }
    @MainActor private func applyEdit(_ id: UUID, operation: OiPhotoEdit) async {
        guard !isEditing, current == .local(id), canEdit else { return }
        isEditing = true
        editedIndex = items.firstIndex(of: .local(id))
        let success = await edit(id, operation)
        if !success { editedIndex = nil }
        resetRotation = UUID(); isEditing = false
    }

    private func toolLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light))
                .accessibilityHidden(true)
            Text(title).font(.custom("Paperlogy-5Medium", size: 20, relativeTo: .body)).tracking(0.4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: 85, minHeight: 88)
        .foregroundStyle(Color(white: 106 / 255))
        .background(Color(white: 244 / 255), in: RoundedRectangle(cornerRadius: 20))
    }

    private func thumbnailLabel(_ title: String) -> some View {
        Text(title)
            .font(.custom("Paperlogy-5Medium", size: 14, relativeTo: .caption))
            .tracking(0.28)
            .foregroundStyle(.white)
    }
}

enum OiPhotoEdit { case rotateLeft, rotate(CGFloat), crop(CGRect) }

/// UIKit's two-touch rotation follows the fingers: right down + left up is clockwise.
private struct OiRotatablePhoto: UIViewRepresentable {
    let image: UIImage
    let resetToken: UUID
    let commit: (CGFloat) -> Void
    func makeUIView(context: Context) -> OiPhotoRotationViewport {
        OiPhotoRotationViewport(image: image)
    }
    func updateUIView(_ view: OiPhotoRotationViewport, context: Context) {
        view.commit = commit
        if view.resetToken != resetToken { view.resetToken = resetToken; view.setPreviewRotation(0) }
    }
}

@MainActor final class OiPhotoRotationViewport: UIView {
    let image: UIImage
    let canvas = UIView()
    let imageView: UIImageView
    var commit: ((CGFloat) -> Void)?
    var resetToken: UUID?
    private(set) var previewRadians: CGFloat = 0
    private lazy var rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotatePhoto(_:)))

    init(image: UIImage) {
        self.image = image; imageView = UIImageView(image: image)
        super.init(frame: .zero)
        backgroundColor = .clear
        canvas.clipsToBounds = true; canvas.isUserInteractionEnabled = false
        imageView.contentMode = .scaleToFill
        canvas.addSubview(imageView); addSubview(canvas)
        addGestureRecognizer(rotation)
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "오른쪽으로 5도 회전", target: self, selector: #selector(rotateRight)),
            UIAccessibilityCustomAction(name: "왼쪽으로 5도 회전", target: self, selector: #selector(rotateLeft))
        ]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard image.size.width > 0, image.size.height > 0 else { return }
        let factor = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        canvas.frame = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        imageView.bounds = CGRect(origin: .zero, size: size)
        imageView.center = CGPoint(x: size.width / 2, y: size.height / 2)
        updateTransform()
    }
    func setPreviewRotation(_ radians: CGFloat) {
        guard radians.isFinite else { return }
        previewRadians = radians; updateTransform()
    }
    private func updateTransform() {
        let scale = OiPhotoRotationGeometry.coverScale(size: image.size, radians: previewRadians)
        imageView.transform = CGAffineTransform(rotationAngle: previewRadians).scaledBy(x: scale, y: scale)
    }
    @objc private func rotatePhoto(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began, .changed: setPreviewRotation(gesture.rotation)
        case .ended:
            guard gesture.rotation.isFinite, abs(gesture.rotation) >= .pi / 360 else { setPreviewRotation(0); return }
            setPreviewRotation(gesture.rotation); commit?(gesture.rotation)
        case .cancelled, .failed: setPreviewRotation(0)
        default: break
        }
    }
    @objc private func rotateRight() -> Bool { commit?(.pi / 36); return true }
    @objc private func rotateLeft() -> Bool { commit?(-.pi / 36); return true }
}
