import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct OiWardrobePhotoEditor: View {
    let slot: OiPhotoSlot
    let look: OiWardrobeLook
    let onSave: (OiWardrobeArtwork) -> Void
    let onClose: (() -> Void)?
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
    @State private var showGuide = true
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
    @State private var guideEdges: [OiPhotoSide: [[[Double]]]] = [:]

    init(slot: OiPhotoSlot, look: OiWardrobeLook, scene: OiWardrobeScene, onClose: (() -> Void)? = nil, onSave: @escaping (OiWardrobeArtwork) -> Void) {
        self.slot = slot; self.look = look; self.onSave = onSave
        self.scene = scene; self.onClose = onClose
        if let design = look.artwork.designs[slot.itemID(in: look)] {
            do {
                let restored = try OiPhotoRenderer.load(design, sources: look.artwork.sources)
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
        !importInProgress && !saving && !restoreFailed && renderTask == nil &&
        !scene.loading && scene.error == nil && scene.photoPreviewError == nil
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("이미지 디자인")
                    .font(CampusStyle.semibold(26)).tracking(0.52)
                    .foregroundStyle(CampusStyle.sectionGreen)
                Spacer(minLength: 8)
                Button("완료", action: save)
                    .font(CampusStyle.medium(20)).tracking(0.4).underline()
                    .foregroundStyle(Color(white: 112 / 255))
                    .padding(.vertical, 9).padding(.leading, 8)
                    .contentShape(Rectangle())
                    .padding(.vertical, -9)
                    .disabled(!canApply).opacity(canApply ? 1 : 0.45)
                    .accessibilityIdentifier("photo-apply")
            }
            .frame(minHeight: 26)
            .contentShape(Rectangle())
            .contextMenu {
                Button("변경 취소", role: .cancel, action: close)
                    .disabled(saving || importInProgress)
            }
            .accessibilityAction(named: "사진 디자인 취소", close)
            ScrollView {
                VStack(spacing: 0) {
                    OiPhotoSidePicker(selection: $side, isEnabled: !importInProgress)
                        .frame(height: 36)
                    uvCanvas.frame(width: 236, height: 237)
                        .padding(.top, 16)
                        .contextMenu {
                            if selectedLayer != nil { transformControls }
                            Toggle("옷 윤곽 보기", isOn: $showGuide)
                            Button("변경 취소", role: .cancel, action: close)
                                .disabled(saving || importInProgress)
                        }
                    photoControls.padding(.top, 16)
                    Text("사진을 눌러 선택한 뒤 드래그∙핀치로 배치하세요.\n주름에도 이미지가 이어지고, 3D 옷에 바로 반영돼요!")
                        .font(CampusStyle.body(10)).tracking(0.2).lineSpacing(3)
                        .foregroundStyle(Color(white: 164 / 255))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)
                    if let message = error ?? scene.error ?? scene.photoPreviewError {
                        Text(message).font(.caption).foregroundStyle(.red)
                            .padding(.top, 8).accessibilityIdentifier("photo-editor-error")
                    }
                    if !restoreFailed && (scene.error != nil || scene.photoPreviewError != nil) {
                        Button("미리보기 다시 시도") {
                            if scene.error != nil { scene.update(look, retry: true) }
                            requestPreview()
                        }.disabled(scene.loading || renderTask != nil)
                    }
                    if importInProgress { ProgressView().accessibilityLabel("사진을 불러오는 중…") }
                }.padding(.bottom, 20)
            }.scrollIndicators(.hidden).accessibilityIdentifier("photo-editor-scroll")
        }
        .padding(.horizontal, 20).padding(.top, 20)
        .foregroundStyle(Color("OiDark"))
        .tint(Color("OiGreen"))
        .preferredColorScheme(.light).environment(\.colorScheme, .light)
        .interactiveDismissDisabled(saving || importInProgress)
        // UIKit owns only the library picker. This avoids SwiftUI SheetBridge
        // dismissing the creation cover while the inline editing panel is active.
        .background {
            OiWardrobePhotoLibrary(isPresented: $isPhotoPickerPresented, limit: pickerSelectionLimit) { results in
                selection = results; importID = UUID()
            }.frame(width: 0, height: 0)
        }
        .onAppear {
            for face in OiPhotoSide.allCases {
                let name = slot.resource(in: look) + "-" + face.rawValue
                if let url = Bundle.main.url(forResource: name, withExtension: "json"),
                   let data = try? Data(contentsOf: url), let edges = try? JSONDecoder().decode([[[Double]]].self, from: data) { guideEdges[face] = edges }
            }
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
        Button {
            guard remaining > 0, !importInProgress, !isPhotoPickerPresented else { return }
            selection = []
            pickerSelectionLimit = remaining
            isPhotoPickerPresented = true
        } label: {
            HStack(spacing: 20) {
                Label("사진 추가", systemImage: "photo.badge.plus")
                Text("\(draft.layers.filter { $0.side == side }.count)/2")
            }.font(CampusStyle.body(16)).tracking(0.32)
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(Color(white: 89 / 255))
                .background(.white, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 3)
                .padding(.vertical, 3).contentShape(Rectangle()).padding(.vertical, -3)
        }.buttonStyle(OiCreationPressStyle()).disabled(remaining == 0 || importInProgress || restoreFailed)
            .accessibilityIdentifier("photo-import")
    }
    @ViewBuilder private var transformControls: some View {
        Button("다른 면으로") {
            guard let index = selectedIndex, OiPhotoEditingLimit.remaining(on: oppositeSide, in: draft.layers) > 0 else { return }
            draft.layers[index].side = oppositeSide
            side = draft.layers[index].side
        }.disabled(OiPhotoEditingLimit.remaining(on: oppositeSide, in: draft.layers) == 0).accessibilityIdentifier("photo-move-side")
        Button("복제") {
            guard var layer = selectedLayer, remaining > 0 else { return }
            layer.id = UUID().uuidString; layer.placement.x = min(0.95, layer.placement.x + 0.06)
            draft.layers.append(layer); selectedID = layer.id
        }.disabled(remaining == 0).accessibilityIdentifier("photo-duplicate")
        Button("뒤로 보내기") { reorder(forward: false) }.disabled(selectedIndex == 0).accessibilityIdentifier("photo-send-back")
        Button("앞으로 가져오기") { reorder(forward: true) }.disabled(selectedIndex == draft.layers.count - 1).accessibilityIdentifier("photo-bring-front")
        Button("배치 초기화") { editSelected { $0.placement = OiPhotoPlacement() } }.accessibilityIdentifier("photo-reset")
        Button("삭제", role: .destructive) { deleteSelected() }.accessibilityIdentifier("photo-delete")
    }
    private var uvCanvas: some View {
        GeometryReader { geometry in
            let edge = geometry.size.width
            ZStack(alignment: .topLeading) {
                slot.preservesOriginalMaterial(in: look) ? Color.white : Color(UIColor(wardrobeRGB: slot.color(in: look)))
                if let image = OiPhotoRenderer.fabricImage(slot.fabric(in: look)) {
                    Image(uiImage: image).resizable().frame(width: edge, height: edge).allowsHitTesting(false)
                }
                ForEach(draft.layers.filter { $0.side == side }) { layer in
                    if let image = draft.assets[layer.source]?.image {
                        Image(uiImage: image).resizable()
                            .frame(width: edge * layer.placement.width, height: edge * layer.placement.width * image.size.height / max(image.size.width, 1))
                            .overlay { if layer.id == selectedID && (isDragging || isTransforming) { Rectangle().stroke(Color("OiGreen"), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) } }
                            .rotationEffect(.degrees(layer.placement.rotation))
                            .position(x: edge * layer.placement.x, y: edge * layer.placement.y)
                            .allowsHitTesting(false)
                    }
                }
                if showGuide {
                    Canvas { context, size in
                        var path = Path()
                        for line in guideEdges[side] ?? [] where line.count == 2 && line.allSatisfy({ $0.count == 2 }) {
                            path.move(to: CGPoint(x: line[0][0] * size.width, y: line[0][1] * size.height))
                            path.addLine(to: CGPoint(x: line[1][0] * size.width, y: line[1][1] * size.height))
                        }
                        context.stroke(path, with: .color(Color("OiGreen").opacity(0.45)), lineWidth: 0.6)
                    }.allowsHitTesting(false)
                }
                if !draft.layers.contains(where: { $0.side == side }) {
                    Text("\(side.title)에 사진을 추가하세요").font(.caption.bold()).padding(10).background(.regularMaterial, in: Capsule()).position(x: edge / 2, y: edge / 2)
                }
            }
            .clipped().contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2).updating($isDragging) { _, active, _ in active = true }.onChanged { value in
                if previousDrag == .zero && !isTransforming { select(at: value.startLocation, edge: edge) }
                defer { previousDrag = value.translation }
                guard !isTransforming else { return }
                editSelected {
                    $0.placement.x = min(1, max(0, $0.placement.x + (value.translation.width - previousDrag.width) / edge))
                    $0.placement.y = min(1, max(0, $0.placement.y + (value.translation.height - previousDrag.height) / edge))
                }
            }.onEnded { _ in previousDrag = .zero })
            .simultaneousGesture(SpatialTapGesture().onEnded { select(at: $0.location, edge: edge) })
            .simultaneousGesture(photoTransformGesture)
            .clipShape(RoundedRectangle(cornerRadius: 20)).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(side.title) 사진 배치용 UV 맵")
            .accessibilityHint("사진을 선택하고 한 손가락으로 이동하세요. 두 손가락을 벌리거나 오므려 크기를 조절하고, 비틀어 회전하세요.")
            .accessibilityActions {
                if selectedLayer != nil {
                    Button("사진 삭제", action: deleteSelected)
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
        guard remaining > 0 else { return }
        draft.assets[asset.id] = asset
        let offset = Double(draft.layers.filter { $0.side == side }.count) * 0.05
        let layer = OiPhotoLayer(source: asset.id, side: side, placement: OiPhotoPlacement(x: 0.5 + offset, y: 0.5 + offset))
        draft.layers.append(layer); selectedID = layer.id; error = nil
    }
    private func deleteSelected() {
        guard let id = selectedID else { return }
        draft.layers.removeAll { $0.id == id }
        selectedID = draft.layers.last { $0.side == side }?.id
        let used = Set(draft.layers.map(\.source)); draft.assets = draft.assets.filter { used.contains($0.key) }
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
        guard phase != .background else { return }
        renderPending = true
        guard renderTask == nil else { return }
        let generation = renderGeneration
        renderTask = Task { @MainActor in
            defer { if renderGeneration == generation { renderTask = nil } }
            while renderPending && !Task.isCancelled {
                renderPending = false
                let image = OiPhotoRenderer.atlas(layers: draft.layers, assets: draft.assets, panelSize: 512, color: slot.color(in: look), fabric: slot.fabric(in: look), transparent: slot.preservesOriginalMaterial(in: look))
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
    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
    private func save() {
        saving = true
        do {
            var artwork = look.artwork
            try artwork.set(OiPhotoDesign(layers: draft.layers), sources: draft.assets.mapValues(\.data), for: slot.itemID(in: look))
            onSave(artwork); close()
        }
        catch { self.error = error.localizedDescription }
        saving = false
    }
}

/// Presents from the editing panel without coupling Photos state to SwiftUI's modal bridge.
struct OiWardrobePhotoLibrary: UIViewControllerRepresentable {
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

/// Native segmented interaction, using the Figma typography and 36pt pill.
private struct OiPhotoSidePicker: UIViewRepresentable {
    @Binding var selection: OiPhotoSide
    var isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: OiPhotoSide.allCases.map(\.title))
        control.backgroundColor = UIColor(white: 223 / 255, alpha: 1)
        control.selectedSegmentTintColor = .white
        control.layer.cornerRadius = 18
        control.clipsToBounds = true
        control.setTitleTextAttributes([
            .font: UIFont(name: "Paperlogy-4Regular", size: 16) ?? .systemFont(ofSize: 16),
            .foregroundColor: UIColor.black
        ], for: .normal)
        control.setTitleTextAttributes([
            .font: UIFont(name: "Paperlogy-6SemiBold", size: 16) ?? .systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: UIColor.black
        ], for: .selected)
        control.accessibilityLabel = "편집할 면"
        control.accessibilityIdentifier = "photo-side"
        control.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        return control
    }
    func updateUIView(_ control: UISegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegmentIndex = OiPhotoSide.allCases.firstIndex(of: selection) ?? 0
        control.isEnabled = isEnabled
    }
    final class Coordinator: NSObject {
        var parent: OiPhotoSidePicker
        init(parent: OiPhotoSidePicker) { self.parent = parent }
        @objc func changed(_ control: UISegmentedControl) {
            guard OiPhotoSide.allCases.indices.contains(control.selectedSegmentIndex) else { return }
            parent.selection = OiPhotoSide.allCases[control.selectedSegmentIndex]
        }
    }
}
