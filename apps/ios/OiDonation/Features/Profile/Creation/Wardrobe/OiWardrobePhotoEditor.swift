import SwiftUI
import PhotosUI

struct OiWardrobePhotoEditor: View {
    let slot: OiPhotoSlot
    let look: OiWardrobeLook
    let onSave: (OiWardrobeArtwork) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var scene: OiWardrobeScene
    @State private var draft = OiPhotoDraft()
    @State private var selection: [PhotosPickerItem] = []
    @State private var isPhotoPickerPresented = false
    @State private var pickerSelectionLimit = OiPhotoDesign.maximumLayers
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

    init(slot: OiPhotoSlot, look: OiWardrobeLook, onSave: @escaping (OiWardrobeArtwork) -> Void) {
        self.slot = slot; self.look = look; self.onSave = onSave
        _scene = State(initialValue: OiWardrobeScene(editingSlot: slot))
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
    private var remaining: Int { OiPhotoDesign.maximumLayers - draft.layers.count }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        if phase != .background { OiWardrobeSurface(scene: scene, look: look) }
                        if scene.loading { ProgressView().padding(14) }
                        else { Label("실시간 미리보기", systemImage: "circle.fill").font(.system(size: 10, weight: .medium)).foregroundStyle(Color("OiGreen")).padding(12) }
                    }
                    .frame(height: max(180, min(280, geometry.size.height * 0.29)))
                    .clipShape(RoundedRectangle(cornerRadius: 22)).padding(.horizontal, 16)
                    HStack {
                        ForEach(Array(["정면", "좌", "우", "뒤"].enumerated()), id: \.offset) { index, name in
                            Button(name) { scene.angle([0, .pi / 2, -.pi / 2, .pi][index]) }
                                .frame(maxWidth: .infinity, minHeight: 32).accessibilityIdentifier("photo-angle-\(index)")
                        }
                    }.font(.caption.bold()).padding(.horizontal, 16)
                    ScrollView {
                        VStack(spacing: 14) {
                            photoControls
                            if let message = error ?? scene.error ?? scene.photoPreviewError {
                                Text(message).font(.caption).foregroundStyle(.red).accessibilityIdentifier("photo-editor-error")
                            }
                            if !restoreFailed && (scene.error != nil || scene.photoPreviewError != nil) {
                                Button("미리보기 다시 시도") {
                                    if scene.error != nil { scene.update(look, retry: true) }
                                    requestPreview()
                                }
                                .buttonStyle(.bordered)
                                .disabled(scene.loading || renderTask != nil)
                            }
                            if importInProgress { ProgressView().accessibilityLabel("사진을 불러오는 중…") }
                            Picker("편집할 면", selection: $side) {
                                ForEach(OiPhotoSide.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).accessibilityIdentifier("photo-side")
                            HStack {
                                Text("\(side.title) UV 펼침도").font(.subheadline.bold())
                                Spacer()
                                Toggle("윤곽", isOn: $showGuide).font(.caption).fixedSize().accessibilityIdentifier("photo-uv-guide")
                            }
                            uvCanvas.frame(width: min(280, geometry.size.width - 36), height: min(280, geometry.size.width - 36))
                            Text("사진을 눌러 선택한 뒤 한 손가락으로 옮기세요. 두 손가락을 벌리거나 오므리면 크기가 바뀌고, 비틀면 회전해요. 3D 옷에도 바로 반영돼요.")
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            layerPicker
                            if selectedLayer != nil { transformControls }
                            Text("사진은 최대 8장까지 추가할 수 있어요. 사진은 축소·압축하여 이 기기의 초안에만 저장해요.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(18).padding(.bottom, 20)
                    }.accessibilityIdentifier("photo-editor-scroll")
                }
            }
            .background(Color.white).foregroundStyle(Color("OiDark"))
            .navigationTitle(slot.title(in: look) + " 디자인").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.disabled(saving).accessibilityIdentifier("photo-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) {
                        if saving { ProgressView().accessibilityHidden(true) }
                        else { Text("적용").bold() }
                    }
                    .accessibilityLabel("적용")
                    .accessibilityValue(saving ? "저장 중" : "")
                    .disabled(importInProgress || saving || restoreFailed || renderTask != nil || scene.loading || scene.error != nil || scene.photoPreviewError != nil)
                    .accessibilityIdentifier("photo-apply")
                }
            }
        }
        .tint(Color("OiGreen")).interactiveDismissDisabled(saving)
        .navigationBarBackButtonHidden(true)
        // Own presentation outside the scrolling controls. The picker must survive
        // preview/layout updates, and its selection limit stays fixed while open.
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selection,
                      maxSelectionCount: pickerSelectionLimit, selectionBehavior: .ordered, matching: .images)
        .onAppear {
            for face in OiPhotoSide.allCases {
                let name = slot.resource(in: look) + "-" + face.rawValue
                if let url = Bundle.main.url(forResource: name, withExtension: "json"),
                   let data = try? Data(contentsOf: url), let edges = try? JSONDecoder().decode([[[Double]]].self, from: data) { guideEdges[face] = edges }
            }
             scene.angle(side == .front ? 0 : .pi); requestPreview()
        }
        .onDisappear { stopPreview(); scene.release() }
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
        .task(id: isPhotoPickerPresented ? [] : selection) { await importPhotos() }
    }

    private var photoControls: some View {
        Button {
            guard remaining > 0, !importInProgress, !isPhotoPickerPresented else { return }
            selection = []
            pickerSelectionLimit = remaining
            isPhotoPickerPresented = true
        } label: {
            Label("사진 추가 \(draft.layers.count)/8", systemImage: "photo.badge.plus")
                .frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(.white)
        }.buttonStyle(.borderedProminent).disabled(remaining == 0 || importInProgress || restoreFailed)
            .accessibilityIdentifier("photo-import")
    }
    private var layerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("사진 목록").font(.subheadline.bold()); Spacer(); Text("나중 사진이 위에 놓여요").font(.caption2).foregroundStyle(.secondary) }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(draft.layers.enumerated()), id: \.element.id) { index, layer in
                        Button {
                            selectedID = layer.id; side = layer.side
                        } label: {
                            VStack(spacing: 4) {
                                if let image = draft.assets[layer.source]?.image {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 52, height: 52).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Text("\(index + 1) · \(layer.side.title)").font(.caption2)
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
                    guard let index = selectedIndex else { return }
                    draft.layers[index].side = side == .front ? .back : .front
                    side = draft.layers[index].side
                }.accessibilityIdentifier("photo-move-side")
                Spacer()
                Button("복제") {
                    guard var layer = selectedLayer, remaining > 0 else { return }
                    layer.id = UUID().uuidString; layer.placement.x = min(0.95, layer.placement.x + 0.06)
                    draft.layers.append(layer); selectedID = layer.id
                }.disabled(remaining == 0).accessibilityIdentifier("photo-duplicate")
                Button("삭제", role: .destructive) { deleteSelected() }.accessibilityIdentifier("photo-delete")
            }.font(.caption.bold())
            HStack {
                Button("뒤로 보내기") { reorder(forward: false) }.disabled(selectedIndex == 0).accessibilityIdentifier("photo-send-back")
                Spacer()
                Button("앞으로 가져오기") { reorder(forward: true) }.disabled(selectedIndex == draft.layers.count - 1).accessibilityIdentifier("photo-bring-front")
            }.font(.caption)
            Button("선택한 사진 배치 초기화") { editSelected { $0.placement = OiPhotoPlacement() } }.font(.subheadline).accessibilityIdentifier("photo-reset")
        }
    }
    private var uvCanvas: some View {
        GeometryReader { geometry in
            let edge = geometry.size.width
            ZStack(alignment: .topLeading) {
                Color(UIColor(wardrobeRGB: slot.color(in: look)))
                if let image = OiPhotoRenderer.fabricImage(slot.fabric(in: look)) {
                    Image(uiImage: image).resizable().frame(width: edge, height: edge).allowsHitTesting(false)
                }
                ForEach(draft.layers.filter { $0.side == side }) { layer in
                    if let image = draft.assets[layer.source]?.image {
                        Image(uiImage: image).resizable()
                            .frame(width: edge * layer.placement.width, height: edge * layer.placement.width * image.size.height / max(image.size.width, 1))
                            .overlay { if layer.id == selectedID { Rectangle().stroke(Color("OiGreen"), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])) } }
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
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color("OiGreen").opacity(0.25)))
            .clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(side.title) 사진 배치용 UV 맵")
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
        let offset = Double(draft.layers.filter { $0.side == side }.count % 4) * 0.05
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
                guard let data = try await pick.loadTransferable(type: Data.self) else { throw OiPhotoDataError.unreadable }
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
                let image = OiPhotoRenderer.atlas(layers: draft.layers, assets: draft.assets, panelSize: 512, color: slot.color(in: look), fabric: slot.fabric(in: look))
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
