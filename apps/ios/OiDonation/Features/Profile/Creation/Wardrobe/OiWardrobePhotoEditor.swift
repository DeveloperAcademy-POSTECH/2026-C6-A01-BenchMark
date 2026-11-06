import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct OiWardrobePhotoEditor: View {
    let slot: OiPhotoSlot
    let look: OiWardrobeLook
    let onSave: (OiWardrobeArtwork) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    let scene: OiWardrobeScene
    @State private var draft = OiPhotoDraft()
    @State private var selection: [PHPickerResult] = []
    @State private var importID = UUID()
    @State private var isPhotoPickerPresented = false
    @State private var pickerSelectionLimit = OiPhotoEditingLimit.perSide
    @State private var selectedID: String?
    @State private var side: OiPhotoSide = .front
    private let layout: OiPhotoPrintLayout?
    @State private var importInProgress = false
    @State private var saving = false
    @State private var error: String?
    @State private var restoreFailed = false
    @State private var previousDrag = CGSize.zero
    @GestureState private var isDragging = false
    @State private var transformStart: OiPhotoPlacement?
    @GestureState private var isTransforming = false
    @State private var renderTask: Task<Void, Never>?
    @State private var renderPending = false
    @State private var renderGeneration = UUID()

    init(slot: OiPhotoSlot, look: OiWardrobeLook, scene: OiWardrobeScene, onSave: @escaping (OiWardrobeArtwork) -> Void) {
        self.slot = slot; self.look = look; self.onSave = onSave
        self.scene = scene
        self.layout = try? OiPhotoPrintLayout.load(resource: slot.resource(in: look))
        if let design = look.artwork.designs[slot.itemID(in: look)] {
            do {
                let restored = try OiPhotoRenderer.load(design, sources: look.artwork.sources, layout: self.layout)
                _draft = State(initialValue: restored)
                _selectedID = State(initialValue: restored.layers.last?.id)
                _side = State(initialValue: restored.layers.last?.side ?? .front)
            } catch {
                _error = State(initialValue: "저장된 사진을 불러오지 못했어요. 취소 후 다시 열어 주세요.")
                _restoreFailed = State(initialValue: true)
            }
        }
    }
    private var selectedIndex: Int? { draft.layers.firstIndex { $0.id == selectedID } }
    private var selectedLayer: OiPhotoLayer? { selectedIndex.map { draft.layers[$0] } }
    private var remaining: Int { OiPhotoEditingLimit.remaining(on: side, in: draft.layers) }
    private var oppositeSide: OiPhotoSide { side == .front ? .back : .front }
    private var canApply: Bool {
        layout != nil && !importInProgress && !saving && !restoreFailed && renderTask == nil &&
        !scene.loading && scene.error == nil && scene.photoPreviewError == nil
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("이미지 디자인").font(CampusStyle.semibold(26)).foregroundStyle(Color("OiDark"))
                Spacer(minLength: 8)
                Button("완료", action: save)
                    .font(CampusStyle.medium(20)).underline().foregroundStyle(Color(white: 0.44))
                    .disabled(!canApply).opacity(canApply ? 1 : 0.45)
                    .frame(minHeight: 44).accessibilityIdentifier("photo-apply")
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15)) }
                    .frame(width: 32, height: 44).accessibilityLabel("사진 디자인 취소")
                    .accessibilityIdentifier("photo-cancel").disabled(saving || importInProgress)
            }
            ScrollView {
                VStack(spacing: 16) {
                    Picker("편집할 면", selection: $side) {
                        ForEach(OiPhotoSide.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("photo-side")
                        .disabled(importInProgress)
                    uvCanvas
                    if !draft.layers.contains(where: { $0.side == side }) {
                        Text("아래 사진 추가 버튼으로 \(side.title)에 사진을 넣어 주세요.")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("photo-empty-instruction")
                    }
                    if !draft.layers.isEmpty { layerPicker }
                    Text("둥근 프레임 안에만 사진이 들어가요.\n드래그로 이동 · 두 손가락으로 크기와 회전 조절")
                        .font(CampusStyle.body(10)).foregroundStyle(Color(white: 0.48))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let message = error ?? scene.error ?? scene.photoPreviewError {
                        Text(message).font(.caption).foregroundStyle(.red).accessibilityIdentifier("photo-editor-error")
                    }
                    if !restoreFailed && (scene.error != nil || scene.photoPreviewError != nil) {
                        Button("미리보기 다시 시도") {
                            if scene.error != nil { scene.update(look, retry: true) }
                            requestPreview()
                        }.disabled(scene.loading || renderTask != nil)
                    }
                    if importInProgress { ProgressView().accessibilityLabel("사진을 불러오는 중…") }
                    if selectedLayer != nil {
                        DisclosureGroup("사진 복제 · 순서 · 초기화") { transformControls.padding(.top, 12) }
                            .font(.subheadline).accessibilityIdentifier("photo-layer-controls")
                    }
                    Text("앞·뒷면 각각 최대 2장 · 완료하면 이 기기의 초안에 저장돼요.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.padding(.bottom, 20)
            }.accessibilityIdentifier("photo-editor-scroll")
            photoControls.padding(.bottom, 8)
        }
        .padding(.horizontal, 20).padding(.top, 12)
        .foregroundStyle(Color("OiDark"))
        .tint(Color("OiGreen"))
        .preferredColorScheme(.light).environment(\.colorScheme, .light)
        .interactiveDismissDisabled(saving || importInProgress)
        // UIKit owns only the library picker. This avoids SwiftUI SheetBridge
        // dismissing both the editing sheet and PhotosPicker in a creation cover.
        .background {
            OiWardrobePhotoLibrary(isPresented: $isPhotoPickerPresented, limit: pickerSelectionLimit) { results in
                selection = results; importID = UUID()
            }.frame(width: 0, height: 0)
        }
        .onAppear {
            if layout == nil { error = "사진 프레임을 불러오지 못했어요. 취소 후 다시 열어 주세요." }
            scene.angle(side == .front ? 0 : .pi); requestPreview()
        }
        .onDisappear { stopPreview() }
        .onChange(of: phase) { _, value in
            // System presentations can temporarily make the scene inactive.
            // Keep the existing preview alive until the app actually backgrounds.
            if value == .background { stopPreview(); scene.release() }
            else if value == .active { requestPreview() }
        }
        .onChange(of: draft.layers) { _, _ in requestPreview() }
        .onChange(of: side) { _, face in
            if selectedLayer?.side != face { selectedID = draft.layers.last { $0.side == face }?.id }
            scene.angle(face == .front ? 0 : .pi)
        }
        // GestureState also resets on cancellation, when onEnded isn't called.
        .onChange(of: isDragging) { _, active in if !active { previousDrag = .zero } }
        .onChange(of: isTransforming) { _, active in if !active { transformStart = nil } }
        // Import after the user finishes/cancels, never while selection is ongoing.
        .task(id: importID) { await importPhotos() }
    }

    private var photoControls: some View {
        HStack(spacing: 10) {
            Button {
                guard remaining > 0, !importInProgress, !isPhotoPickerPresented else { return }
                selection = []
                pickerSelectionLimit = remaining
                isPhotoPickerPresented = true
            } label: {
                HStack(spacing: 8) {
                    Label("사진 추가", systemImage: "photo.badge.plus")
                    Text("\(draft.layers.filter { $0.side == side }.count)/2")
                }.font(CampusStyle.body(16))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(Color(white: 0.35))
                    .background(.white, in: Capsule())
                    .shadow(color: .black.opacity(0.14), radius: 3)
            }.buttonStyle(OiCreationPressStyle()).disabled(layout == nil || remaining == 0 || importInProgress || restoreFailed || saving)
                .accessibilityIdentifier("photo-import")
            Button(role: .destructive, action: deleteSelected) {
                Label("사진 삭제", systemImage: "trash")
                    .font(CampusStyle.body(15)).frame(minWidth: 100, minHeight: 44)
                    .background(.white, in: Capsule())
            }.buttonStyle(.plain).foregroundStyle(.red)
                .disabled(selectedLayer == nil || importInProgress || saving || restoreFailed)
                .opacity(selectedLayer == nil ? 0.4 : 1)
                .accessibilityHint("선택한 사진만 삭제해요. 완료를 눌러 저장할 수 있어요.")
                .accessibilityIdentifier("photo-delete")
        }
    }
    private var layerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("\(side.title) 사진 선택").font(.caption.bold()); Spacer(); Text("선택 후 아래에서 삭제").font(.caption2).foregroundStyle(.secondary) }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(draft.layers.enumerated()).filter { $0.element.side == side }, id: \.element.id) { index, layer in
                        Button {
                            selectedID = layer.id; side = layer.side
                        } label: {
                            HStack(spacing: 5) {
                                if let image = draft.assets[layer.source]?.image {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 36, height: 36).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Text("사진 \(index + 1)").font(.caption2)
                                if selectedID == layer.id { Image(systemName: "checkmark.circle.fill").font(.caption) }
                            }.padding(5).background(selectedID == layer.id ? Color("OiGreen").opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain).accessibilityLabel("사진 \(index + 1), \(layer.side.title)")
                            .accessibilityIdentifier("photo-layer-\(index)")
                    }
                }
            }
        }
    }
    private var transformControls: some View {
        VStack(spacing: 12) {
            HStack {
                Button("다른 면으로") {
                    guard let index = selectedIndex, OiPhotoEditingLimit.remaining(on: oppositeSide, in: draft.layers) > 0 else { return }
                    draft.layers[index].side = side == .front ? .back : .front
                    side = draft.layers[index].side
                }.disabled(OiPhotoEditingLimit.remaining(on: oppositeSide, in: draft.layers) == 0).accessibilityIdentifier("photo-move-side")
                Spacer()
                Button("복제") {
                    guard var layer = selectedLayer, remaining > 0 else { return }
                    layer.id = UUID().uuidString; layer.placement.x = min(0.95, layer.placement.x + 0.06)
                    draft.layers.append(layer); selectedID = layer.id
                }.disabled(remaining == 0).accessibilityIdentifier("photo-duplicate")
            }.font(.caption.bold())
            HStack {
                Button("뒤로 보내기") { reorder(forward: false) }.disabled(selectedIndex == 0).accessibilityIdentifier("photo-send-back")
                Spacer()
                Button("앞으로 가져오기") { reorder(forward: true) }.disabled(selectedIndex == draft.layers.count - 1).accessibilityIdentifier("photo-bring-front")
            }.font(.caption)
            Button("프레임에 사진 채우기") {
                guard let layer = selectedLayer, let image = draft.assets[layer.source]?.image, let layout else { return }
                editSelected { $0.placement = layout[side].placement(for: image) }
            }.font(.subheadline).accessibilityIdentifier("photo-reset")
        }
    }
    @ViewBuilder private var uvCanvas: some View {
        if let frame = layout?[side] {
            Color.clear.aspectRatio(frame.width / frame.height, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        photoCanvas(frame: frame, width: geometry.size.width)
                    }
                }
                .frame(maxHeight: 240)
                .frame(maxWidth: .infinity)
        }
    }
    private func photoCanvas(frame: OiPhotoPrintFrame, width: CGFloat) -> some View {
        let viewport = OiPhotoPrintViewport(frame: frame, width: width)
        let edge = viewport.panelEdge
        let shape = RoundedRectangle(cornerRadius: frame.radius * edge, style: .circular)
        return OiPhotoLayerCanvas(layers: draft.layers, assets: draft.assets, side: side,
            selectedID: selectedID, frame: frame, width: width,
            background: Color(UIColor(wardrobeRGB: slot.color(in: look))),
            fabric: OiPhotoRenderer.fabricImage(slot.fabric(in: look)))
            .overlay(shape.strokeBorder(Color("OiGreen"), lineWidth: 1.5).allowsHitTesting(false))
            .contentShape(shape)
            .gesture(DragGesture(minimumDistance: 2).updating($isDragging) { _, active, _ in active = true }.onChanged { value in
                if previousDrag == .zero && !isTransforming { select(at: viewport.panelPoint(value.startLocation), edge: edge) }
                defer { previousDrag = value.translation }
                guard !isTransforming else { return }
                editSelected {
                    $0.placement.x = min(1, max(0, $0.placement.x + (value.translation.width - previousDrag.width) / edge))
                    $0.placement.y = min(1, max(0, $0.placement.y + (value.translation.height - previousDrag.height) / edge))
                }
            }.onEnded { _ in previousDrag = .zero })
            .simultaneousGesture(SpatialTapGesture().onEnded { select(at: viewport.panelPoint($0.location), edge: edge) })
            .simultaneousGesture(photoTransformGesture)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(side.title) 둥근 사진 프레임")
            .accessibilityHint("사진을 선택하고 한 손가락으로 이동하세요. 두 손가락을 벌리거나 오므려 크기를 조절하고, 비틀어 회전하세요.")
            .accessibilityActions {
                if selectedLayer != nil {
                    Button("사진 확대") { editSelected { $0.placement.width = min(1.5, $0.placement.width * 1.1) } }
                    Button("사진 축소") { editSelected { $0.placement.width = max(0.03, $0.placement.width / 1.1) } }
                    Button("사진 시계 방향 회전") { editSelected { $0.placement.rotation = wrappedRotation($0.placement.rotation + 15) } }
                    Button("사진 반시계 방향 회전") { editSelected { $0.placement.rotation = wrappedRotation($0.placement.rotation - 15) } }
                    Button("사진 왼쪽 이동") { editSelected { $0.placement.x = max(0, $0.placement.x - 0.05) } }
                    Button("사진 오른쪽 이동") { editSelected { $0.placement.x = min(1, $0.placement.x + 0.05) } }
                    Button("사진 위로 이동") { editSelected { $0.placement.y = max(0, $0.placement.y - 0.05) } }
                    Button("사진 아래로 이동") { editSelected { $0.placement.y = min(1, $0.placement.y + 0.05) } }
                }
            }
            .accessibilityIdentifier("photo-uv-canvas")
    }
    private var photoTransformGesture: some Gesture {
        MagnifyGesture().simultaneously(with: RotateGesture())
            .updating($isTransforming) { _, active, _ in active = true }
            .onChanged { value in
                guard let layer = selectedLayer else { return }
                // Both recognizers use the same starting placement, so rotating
                // and pinching together never compound intermediate updates.
                let start = transformStart ?? layer.placement
                transformStart = start
                editSelected {
                    if let scale = value.first?.magnification, scale.isFinite {
                        $0.placement.width = min(1.5, max(0.03, start.width * scale))
                    }
                    if let degrees = value.second?.rotation.degrees, degrees.isFinite {
                        $0.placement.rotation = wrappedRotation(start.rotation + degrees)
                    }
                }
            }
            .onEnded { _ in transformStart = nil }
    }
    private func wrappedRotation(_ degrees: Double) -> Double {
        // Keep continuous turns valid for persisted placements (-180...180).
        let remainder = (degrees + 180).truncatingRemainder(dividingBy: 360)
        return (remainder < 0 ? remainder + 360 : remainder) - 180
    }
    private func select(at point: CGPoint, edge: CGFloat) {
        guard let frame = layout?[side], frame.path(edge: edge).contains(point) else { return }
        for layer in draft.layers.reversed() where layer.side == side {
            guard let image = draft.assets[layer.source]?.image else { continue }
            let dx = point.x / edge - layer.placement.x, dy = point.y / edge - layer.placement.y
            let radians = layer.placement.rotation * .pi / 180
            let x = dx * cos(radians) + dy * sin(radians), y = -dx * sin(radians) + dy * cos(radians)
            if abs(x) <= layer.placement.width / 2 && abs(y) <= layer.placement.width * image.size.height / max(image.size.width, 1) / 2 { selectedID = layer.id; return }
        }
    }
    private func editSelected(_ edit: (inout OiPhotoLayer) -> Void) {
        guard let index = selectedIndex else { return }; edit(&draft.layers[index])
    }
    private func add(_ asset: OiPhotoImageAsset) {
        guard remaining > 0, let frame = layout?[side] else { return }
        draft.assets[asset.id] = asset
        let layer = OiPhotoLayer(source: asset.id, side: side, placement: frame.placement(for: asset.image))
        draft.layers.append(layer); selectedID = layer.id; error = nil
    }
    private func deleteSelected() {
        guard let id = selectedID else { return }
        selectedID = draft.remove(id, on: side)
    }
    private func reorder(forward: Bool) {
        guard let index = selectedIndex else { return }
        let layer = draft.layers.remove(at: index)
        if forward { draft.layers.append(layer) } else { draft.layers.insert(layer, at: 0) }
    }
    @MainActor private func importPhotos() async {
        guard !isPhotoPickerPresented, !selection.isEmpty else { return }
        let picks = Array(selection.prefix(remaining))
        importInProgress = true; error = nil
        defer { importInProgress = false; selection = [] }
        var failures = 0
        for pick in picks {
            do {
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    pick.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: error ?? OiPhotoDataError.unreadable) }
                    }
                }
                try Task.checkCancellation()
                let asset = try OiPhotoRenderer.asset(data)
                try Task.checkCancellation(); add(asset)
            } catch is CancellationError { return }
            catch { failures += 1 }
        }
        if failures > 0 { error = "사진 \(failures)장을 불러오지 못했어요. 나머지 사진은 추가했어요." }
    }
    private func requestPreview() {
        guard phase != .background, let layout else { return }
        renderPending = true
        guard renderTask == nil else { return }
        let generation = renderGeneration
        renderTask = Task { @MainActor in
            defer { if renderGeneration == generation { renderTask = nil } }
            while renderPending && !Task.isCancelled {
                renderPending = false
                let image = OiPhotoRenderer.atlas(layers: draft.layers, assets: draft.assets, panelSize: 512, color: slot.color(in: look), fabric: slot.fabric(in: look), transparent: slot.preservesOriginalMaterial(in: look), layout: layout)
                if let cg = image.cgImage { await scene.setPhotoPreview(cg) }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
    private func stopPreview() {
        renderGeneration = UUID()
        renderTask?.cancel()
        renderTask = nil
        renderPending = false
    }
    private func save() {
        saving = true
        do {
            var artwork = look.artwork
            try artwork.set(OiPhotoDesign(layers: draft.layers), sources: draft.assets.mapValues(\.data), for: slot.itemID(in: look))
            onSave(artwork); dismiss()
        }
        catch { self.error = error.localizedDescription }
        saving = false
    }
}

/// Presents from the editing sheet without coupling Photos state to SwiftUI's modal bridge.
private struct OiWardrobePhotoLibrary: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let limit: Int
    let onSelection: ([PHPickerResult]) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }
    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, controller.presentedViewController == nil, !context.coordinator.presenting else { return }
        context.coordinator.presenting = true
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = max(1, limit)
        configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        controller.present(picker, animated: true)
    }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: OiWardrobePhotoLibrary
        var presenting = false
        init(parent: OiWardrobePhotoLibrary) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true) { [self] in
                presenting = false
                parent.isPresented = false
                parent.onSelection(results)
            }
        }
    }
}

/// Draw from the source on each update. The print clip belongs to the canvas,
/// never to a photo's moving/scaling view or a previously clipped bitmap.
struct OiPhotoLayerCanvas: View {
    let layers: [OiPhotoLayer]
    let assets: [String: OiPhotoImageAsset]
    let side: OiPhotoSide
    let selectedID: String?
    let frame: OiPhotoPrintFrame
    let width: CGFloat
    var background: Color = .clear
    var fabric: UIImage?

    var body: some View {
        let viewport = OiPhotoPrintViewport(frame: frame, width: width)
        let edge = viewport.panelEdge
        Canvas { context, _ in
            context.translateBy(x: -viewport.rect.minX, y: -viewport.rect.minY)
            // Set the clip before any photo transform, as OiPhotoRenderer.atlas does.
            context.clip(to: Path(frame.path(edge: edge)))
            let panel = CGRect(x: 0, y: 0, width: edge, height: edge)
            context.fill(Path(panel), with: .color(background))
            if let fabric { context.draw(Image(uiImage: fabric), in: panel) }
            for layer in layers where layer.side == side {
                guard let image = assets[layer.source]?.image else { continue }
                let placement = layer.placement
                let width = edge * placement.width
                let height = width * image.size.height / max(image.size.width, 1)
                let bounds = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
                // A fresh context keeps both the frame and other photos stationary.
                var photo = context
                photo.translateBy(x: edge * placement.x, y: edge * placement.y)
                photo.rotate(by: .degrees(placement.rotation))
                photo.draw(Image(uiImage: image), in: bounds)
                if layer.id == selectedID {
                    photo.stroke(Path(bounds), with: .color(Color("OiGreen")),
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
        }
        .frame(width: viewport.rect.width, height: viewport.rect.height)
    }
}
