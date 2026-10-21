// Created by 이돈혁

import PhotosUI
import SwiftUI
import UIKit

struct PhotoCollageEditor: View {
    let manual: Bool
    @State private var photos = Array(repeating: CollagePhoto(), count: 4)
    @State private var automaticSelection: [PhotosPickerItem] = []
    @State private var slotSelection: PhotosPickerItem?
    @State private var template: CollageTemplate = .grid
    @State private var canvasRatio: CGFloat = 9 / 16
    @State private var selectedSlot = 0
    @State private var requestedSlot = 0
    @State private var showsPicker = false
    @State private var loading = false
    @State private var loadFailed = false
    @State private var loadRequest = UUID()
    @State private var completedLoadRequest: UUID?
    @State private var notice: String?
    @State private var result: CollageExport?
    private let loader = CollageImageLoader()

    private var arrangement: CollageArrangement? {
        if manual { return CollageArrangement(aspectRatio: canvasRatio, frames: template.frames) }
        let images = photos.compactMap(\.image)
        return CollageArrangement.automatic(aspectRatios: images.map { $0.size.width / $0.size.height })
    }

    private var visiblePhotos: [CollagePhoto] {
        manual ? Array(photos.prefix(template.frames.count)) : photos.filter { $0.image != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(manual ? "틀을 고르고 칸을 눌러 사진을 넣어 주세요. 선택한 사진은 드래그하거나 두 손가락으로 확대할 수 있어요." :
                        "사진 1~4장을 선택하면 자르거나 늘리지 않고 하나의 직사각형으로 맞춰 드려요.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if manual { templateControls }
                if let arrangement {
                    CollageCanvas(photos: $photos, arrangement: arrangement, manual: manual,
                                  selectedSlot: selectedSlot, onSelect: selectSlot)
                        .frame(height: 400)
                        .allowsHitTesting(!loading)
                } else {
                    ContentUnavailableView("사진을 선택해 주세요", systemImage: "photo.on.rectangle.angled",
                                           description: Text("사진의 가로세로 비율에 맞춰 배치가 자동으로 정해져요."))
                        .frame(minHeight: 220)
                }
                if loading { ProgressView("사진을 불러오는 중이에요…") }
                if let notice {
                    Text(notice).font(.callout).foregroundStyle(.secondary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                if loadFailed {
                    Button("다시 불러오기") { loadRequest = UUID() }
                        .buttonStyle(.bordered).disabled(loading)
                }
                if manual { slotControls } else {
                    PhotosPicker(selection: $automaticSelection, maxSelectionCount: 4,
                                 selectionBehavior: .ordered, matching: .images) {
                        Label(visiblePhotos.isEmpty ? "사진 1~4장 선택" : "사진 다시 선택", systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).disabled(loading)
                }
                Button(action: export) {
                    Label("완성 이미지", systemImage: "checkmark")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(loading || visiblePhotos.isEmpty || visiblePhotos.contains { $0.image == nil })
                Text("사진은 기기 안에서만 처리해요. 완성 이미지는 긴 변 최대 2,048px로 만들어져요.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle(manual ? "레이아웃" : "콜라주")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color("OiGreen"))
        .photosPicker(isPresented: $showsPicker, selection: $slotSelection, matching: .images)
        .onChange(of: automaticSelection) { _, _ in loadRequest = UUID() }
        .onChange(of: slotSelection) { _, _ in loadRequest = UUID() }
        .task(id: loadRequest) {
            loading = false
            let request = loadRequest
            guard completedLoadRequest != request else { return }
            if manual { await loadSlot() } else { await loadAutomatic() }
            if !Task.isCancelled && !loadFailed { completedLoadRequest = request }
        }
        .sheet(item: $result) { CollageResultView(result: $0) }
    }

    private var templateControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("분할 틀", selection: $template) {
                ForEach(CollageTemplate.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("이미지 비율", selection: $canvasRatio) {
                Text("스토리 9:16").tag(CGFloat(9) / 16)
                Text("세로 4:5").tag(CGFloat(4) / 5)
                Text("정사각형").tag(CGFloat(1))
            }
            .pickerStyle(.menu)
        }
        .disabled(loading)
        .onChange(of: template) { _, value in
            selectedSlot = min(selectedSlot, value.frames.count - 1)
            requestedSlot = selectedSlot
            slotSelection = nil
            loadFailed = false
            notice = nil
            for index in photos.indices { photos[index].crop = CollageCrop() }
        }
        .onChange(of: canvasRatio) { _, _ in
            for index in photos.indices { photos[index].crop = CollageCrop() }
        }
    }

    private var slotControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(selectedSlot + 1)번 칸").font(.headline)
            Button { selectSlot(selectedSlot, openPicker: true) } label: {
                Label(photos[selectedSlot].image == nil ? "사진 추가" : "사진 교체", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            if photos[selectedSlot].image != nil {
                cropSlider("확대", value: $photos[selectedSlot].crop.zoom, range: 1...4)
                cropSlider("좌우 위치", value: $photos[selectedSlot].crop.x, range: -1.5...1.5)
                cropSlider("상하 위치", value: $photos[selectedSlot].crop.y, range: -1.5...1.5)
                HStack {
                    Button("구도 초기화") { photos[selectedSlot].crop = CollageCrop() }
                    Spacer()
                    Button("사진 제거", role: .destructive) { photos[selectedSlot] = CollagePhoto() }
                }.buttonStyle(.bordered).frame(minHeight: 44)
            }
        }
        .disabled(loading)
    }

    private func cropSlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }

    private func selectSlot(_ index: Int, openPicker: Bool = false) {
        guard !loading else { return }
        selectedSlot = index
        if openPicker || photos[index].image == nil {
            requestedSlot = index
            loadFailed = false
            notice = nil
            slotSelection = nil
            showsPicker = true
        }
    }

    private func loadAutomatic() async {
        guard !manual, !automaticSelection.isEmpty else { return }
        loading = true
        loadFailed = false
        notice = nil
        defer { if !Task.isCancelled { loading = false } }
        do {
            var loaded: [CollagePhoto] = []
            for item in automaticSelection {
                let image = try await loader.load(item)
                try Task.checkCancellation()
                loaded.append(CollagePhoto(image: image))
            }
            photos = loaded
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            notice = error.localizedDescription
            loadFailed = true
        }
    }

    private func loadSlot() async {
        guard manual, let item = slotSelection else { return }
        let index = requestedSlot
        selectedSlot = index
        loading = true
        loadFailed = false
        notice = nil
        defer { if !Task.isCancelled { loading = false } }
        do {
            let image = try await loader.load(item)
            try Task.checkCancellation()
            photos[index] = CollagePhoto(image: image)
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            notice = "\(index + 1)번 칸: \(error.localizedDescription)"
            loadFailed = true
        }
    }

    private func export() {
        guard let arrangement else { return }
        do {
            result = CollageExport(image: try CollageRenderer.render(photos: visiblePhotos, arrangement: arrangement, cropped: manual))
        } catch { notice = error.localizedDescription }
    }
}

struct CollageExport: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct CollageResultView: View {
    let result: CollageExport
    @Environment(\.dismiss) private var dismiss
    @State private var saving = false
    @State private var saved = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(uiImage: result.image).resizable().scaledToFit()
                        .accessibilityLabel("완성된 콜라주")
                    Button(saved ? "사진 앱에 저장됨" : "사진 앱에 저장") { saving = true }
                        .buttonStyle(.borderedProminent).disabled(saving || saved)
                    ShareLink(item: Image(uiImage: result.image),
                              preview: SharePreview("콜라주", image: Image(uiImage: result.image))) {
                        Label("이미지 공유", systemImage: "square.and.arrow.up")
                    }.buttonStyle(.bordered)
                    if saving { ProgressView("저장 중…") }
                    if let notice { Text(notice).font(.callout).accessibilityAddTraits(.updatesFrequently) }
                }.padding(20)
            }
            .navigationTitle("완성 이미지").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
            .task(id: saving) {
                guard saving else { return }
                defer { saving = false }
                do {
                    try await ARPhotoLibraryService().save(result.image)
                    saved = true
                    notice = "사진 보관함에 저장했어요."
                } catch { notice = "저장 실패: \(error.localizedDescription)" }
            }
        }
    }
}

#Preview { NavigationStack { PhotoCollageEditor(manual: true) } }
#Preview { NavigationStack { PhotoCollageEditor(manual: false) } }
