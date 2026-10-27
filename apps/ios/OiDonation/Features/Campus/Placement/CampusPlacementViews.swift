import SwiftUI

struct CampusPlacementEditor: View {
    let scene: CampusExploreScene
    let placements: CampusPlacementStore
    let stories: [CampusStory]
    var editing: CampusPlacement? = nil
    @State private var storyID = ""
    @State private var height = 1.0
    @State private var heading = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(editing == nil ? "오이 배치 테스트" : "오이 위치 수정").font(.headline)
                Spacer()
                Button("취소") { scene.endPlacement() }
            }
            Text(scene.placementMessage).font(.caption).accessibilityIdentifier("placement.coordinate")
            Picker("연결할 예시 이야기", selection: $storyID) {
                ForEach(stories) { story in Text("\(story.title) · \(story.location)").tag(story.id) }
            }.pickerStyle(.menu).disabled(editing != nil)
            CampusPlacementTools(scene: scene)
            CampusPlacementDimensions(height: $height, heading: $heading)
            Text("이 iPhone에만 저장되는 예시입니다. 지도는 미측량 지형이며 GPS·현장 AR 오차는 별도입니다.")
                .font(.caption2).foregroundStyle(.secondary)
            Button(editing == nil ? "이 위치에 저장" : "변경한 위치 저장") { save() }
                .buttonStyle(.borderedProminent).tint(CampusStyle.green).frame(maxWidth: .infinity)
                .disabled(scene.draftPoint == nil || storyID.isEmpty || !placements.ready)
                .accessibilityIdentifier("placement.save")
        }
        .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 12).padding(.bottom, 8)
        .onAppear {
            if let editing {
                storyID = editing.storyID; height = editing.heightMeters; heading = editing.headingDegrees
                scene.setDraft(editing)
            } else { storyID = stories.first?.id ?? "" }
        }
        .onChange(of: scene.draftPoint) { _, _ in preview() }
        .onChange(of: height) { _, _ in preview() }
        .onChange(of: heading) { _, _ in preview() }
    }
    private func preview() { scene.updateDraft(height: height, heading: heading) }
    private func save() {
        guard let point = scene.draftPoint, let data = scene.data else { return }
        let coordinate = data.coordinate(point)
        let record = CampusPlacement(id: editing?.id ?? UUID(), storyID: storyID, latitude: coordinate.latitude,
                                     longitude: coordinate.longitude, heightMeters: height, headingDegrees: heading)
        let saved = editing == nil ? placements.save(record) : placements.update(record)
        if saved { scene.endPlacement() }
    }
}

struct CampusPlacementList: View {
    let placements: CampusPlacementStore
    let stories: CampusStoryStore
    let onAR: (CampusPlacement) -> Void
    let onEdit: (CampusPlacement) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var deletion: CampusPlacement?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("이 iPhone에서 저장한 예시 배치입니다. 목표 지점 25m 안에서 위치 정확도를 확인한 뒤 AR로 볼 수 있어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = placements.error { Text(error).foregroundStyle(.red) }
                }
                ForEach(placements.placements) { placement in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(stories.story(placement.storyID)?.title ?? "예시 이야기").font(.headline)
                        Text(String(format: "%.6f, %.6f · %.1fm · %.0f°", placement.latitude,
                                    placement.longitude, placement.heightMeters, placement.headingDegrees))
                            .font(.caption).foregroundStyle(.secondary)
                        Button { onAR(placement) } label: { Label("현장에서 AR로 보기", systemImage: "arkit") }
                            .buttonStyle(.borderless)
                        HStack {
                            Button("위치 수정", systemImage: "mappin.and.ellipse") { onEdit(placement) }
                                .accessibilityIdentifier("placement.edit.\(placement.id)")
                            Spacer()
                            Button("삭제", systemImage: "trash", role: .destructive) { deletion = placement }
                                .accessibilityIdentifier("placement.delete.\(placement.id)")
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 4)
                    .swipeActions(allowsFullSwipe: false) {
                        Button("삭제", role: .destructive) { deletion = placement }
                    }
                }
                if placements.placements.isEmpty { Text("지도에서 ‘예시 오이 배치’를 눌러 시작해 주세요.") }
            }
            .navigationTitle("저장한 오이").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
            .confirmationDialog("이 오이를 지도에서 삭제할까요?", isPresented: Binding(
                get: { deletion != nil }, set: { if !$0 { deletion = nil } }
            ), titleVisibility: .visible, presenting: deletion) { placement in
                Button("오이 삭제", role: .destructive) { placements.remove(placement.id) }
            } message: { _ in
                Text("저장한 배치만 삭제됩니다. 연결된 예시 이야기와 수집 기록은 유지됩니다.")
            }
        }
    }
}

struct CampusPlacementDetail: View {
    let placement: CampusPlacement
    let placements: CampusPlacementStore
    let stories: CampusStoryStore
    let onEdit: () -> Void
    let onAR: () -> Void
    let onStory: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeletion = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(stories.story(placement.storyID)?.title ?? "예시 이야기").font(.headline)
                    Text(String(format: "위도 %.6f · 경도 %.6f", placement.latitude, placement.longitude)).font(.caption)
                    Text(String(format: "키 %.1fm · 방향 %.0f°", placement.heightMeters, placement.headingDegrees)).font(.caption)
                    if let error = placements.error { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button("이야기 보기", systemImage: "book", action: onStory)
                    Button("현장에서 AR로 보기", systemImage: "arkit", action: onAR)
                    Button("위치 수정", systemImage: "mappin.and.ellipse", action: onEdit)
                        .accessibilityIdentifier("placement.detail.edit")
                    Button("오이 삭제", systemImage: "trash", role: .destructive) { confirmingDeletion = true }
                        .accessibilityIdentifier("placement.detail.delete")
                }
            }
            .navigationTitle("배치한 오이").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
            .confirmationDialog("이 오이를 지도에서 삭제할까요?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("오이 삭제", role: .destructive) {
                    if placements.remove(placement.id) { dismiss() }
                }
            } message: {
                Text("저장한 배치만 삭제됩니다. 연결된 예시 이야기와 수집 기록은 유지됩니다.")
            }
        }
    }
}
