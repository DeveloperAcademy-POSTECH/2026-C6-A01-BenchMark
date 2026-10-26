import SwiftUI

struct CampusPlacementEditor: View {
    let scene: CampusExploreScene
    let placements: CampusPlacementStore
    let stories: [CampusStory]
    @State private var storyID = ""
    @State private var height = 1.0
    @State private var heading = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("오이 배치 테스트").font(.headline)
                Spacer()
                Button("취소") { scene.endPlacement() }
            }
            Text(scene.placementMessage).font(.caption).accessibilityIdentifier("placement.coordinate")
            Picker("연결할 예시 이야기", selection: $storyID) {
                ForEach(stories) { story in Text("\(story.title) · \(story.location)").tag(story.id) }
            }.pickerStyle(.menu)
            HStack {
                Text("실제 키 \(height, specifier: "%.1f")m").frame(width: 100, alignment: .leading)
                Slider(value: $height, in: 0.4...2, step: 0.1).accessibilityLabel("실제 오이 높이")
            }.font(.caption)
            HStack {
                Text("방향 \(Int(heading))°").frame(width: 100, alignment: .leading)
                Slider(value: $heading, in: 0...359, step: 1).accessibilityLabel("북쪽 기준 시계 방향")
            }.font(.caption)
            Text("이 iPhone에만 저장됩니다. 지도 오이는 알아보기 쉽게 확대 표시해요. 실제 기부·스토리 공개 승인과 무관한 예시 배치입니다.")
                .font(.caption2).foregroundStyle(.secondary)
            Button("이 위치에 저장") { save() }
                .buttonStyle(.borderedProminent).tint(CampusStyle.green).frame(maxWidth: .infinity)
                .disabled(scene.draftPoint == nil || storyID.isEmpty || !placements.ready)
                .accessibilityIdentifier("placement.save")
        }
        .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 12).padding(.bottom, 8)
        .onAppear { storyID = stories.first?.id ?? "" }
        .onChange(of: scene.draftPoint) { _, _ in preview() }
        .onChange(of: height) { _, _ in preview() }
        .onChange(of: heading) { _, _ in preview() }
    }
    private func preview() { scene.updateDraft(height: height, heading: heading) }
    private func save() {
        guard let point = scene.draftPoint, let data = scene.data else { return }
        let coordinate = data.coordinate(point)
        if placements.save(CampusPlacement(storyID: storyID, latitude: coordinate.latitude,
                                           longitude: coordinate.longitude, heightMeters: height,
                                           headingDegrees: heading)) { scene.endPlacement() }
    }
}

struct CampusPlacementList: View {
    let placements: CampusPlacementStore
    let stories: CampusStoryStore
    let onAR: (CampusPlacement) -> Void
    @Environment(\.dismiss) private var dismiss

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
                    }.padding(.vertical, 4)
                    .swipeActions { Button("삭제", role: .destructive) { placements.remove(placement.id) } }
                }
                if placements.placements.isEmpty { Text("지도에서 ‘오이 배치’를 눌러 시작해 주세요.") }
            }
            .navigationTitle("저장한 오이").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
    }
}
