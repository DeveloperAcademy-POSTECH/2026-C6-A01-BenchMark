import SwiftUI

struct CampusWriterRegistration: View {
    let store: CampusSharedStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("운영진에게 받은 작성 코드") {
                    Text("기부 증빙을 운영진이 검토하고 승인한 뒤 코드를 받을 수 있어요. 이는 학교의 공식 납입 확인이나 영수증이 아닙니다.")
                    SecureField("작성 코드", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text("코드는 한 번만 등록할 수 있어요. 이 기기에 저장되는 작성 권한은 30일간 유효하며, 재발급은 운영진에게 요청해 주세요.").font(.footnote)
                    if let error { Text(error).foregroundStyle(.red) }
                    Button(busy ? "확인 중…" : "작성 권한 등록") {
                        busy = true; error = nil
                        Task {
                            defer { busy = false }
                            do { try await store.register(code: code); code = ""; dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(busy || code.isEmpty || !store.configured)
                }
            }.navigationTitle("글 작성 승인").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
        }
    }
}

struct CampusSharedEditor: View {
    let scene: CampusExploreScene
    let store: CampusSharedStore
    let editing: CampusSharedOi?
    @State private var id = UUID()
    @State private var height = 1.0
    @State private var heading = 0.0
    @State private var name = ""
    @State private var title = ""
    @State private var story = ""
    @State private var writing = false
    @State private var busy = false
    @State private var error: String?
    @State private var frozenRequest: CampusSharedDraft?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(editing == nil ? "공유 오이 심기" : "오이 수정").font(.headline); Spacer(); Button("취소") { scene.endPlacement() } }
            Text(scene.placementMessage).font(.caption)
            CampusPlacementTools(scene: scene)
            CampusPlacementDimensions(height: $height, heading: $heading)
            Button(editing == nil ? "이 위치에 이야기 작성" : "변경한 위치·내용 확인") { writing = true }
                .buttonStyle(.borderedProminent).disabled(scene.draftPoint == nil)
            Text("지도는 미측량 지형이며 GPS·현장 AR 오차는 별도입니다. 실제 출입 가능한 장소인지 공개 전에 검토합니다.").font(.caption2)
        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22)).padding(12)
            .onAppear {
                if let editing {
                    id = editing.id; height = editing.heightMeters; heading = editing.headingDegrees
                    name = editing.displayName; title = editing.title; story = editing.story
                    scene.setDraft(editing.placement)
                }
            }
            .onChange(of: scene.draftPoint) { _, _ in preview() }
            .onChange(of: height) { _, _ in preview() }
            .onChange(of: heading) { _, _ in preview() }
            .sheet(isPresented: $writing) {
                NavigationStack {
                    Form {
                        Section("다른 이용자에게 보이는 이야기") {
                            TextField("공개 이름 (40자)", text: $name)
                            TextField("제목 (80자)", text: $title)
                            TextEditor(text: $story).frame(minHeight: 160).accessibilityLabel("이야기 본문")
                            Text("\(story.utf16.count)/2000 · 증빙이나 계좌 정보는 쓰지 마세요.").font(.caption)
                        }.disabled(busy || frozenRequest != nil)
                        Section {
                            Text("저장 또는 수정하면 공개 검토 대기가 됩니다. 공개 전까지 지도에는 표시되지 않아요.").font(.footnote)
                            if let error { Text(error).foregroundStyle(.red) }
                            if frozenRequest != nil { Text("이전 저장의 결과를 확인하고 있어요. 같은 내용으로 재시도하거나, 닫고 내 오이 목록을 새로고침해 주세요.").font(.caption) }
                            Button(busy ? "저장 중…" : "저장 요청") { save() }.disabled(busy || !valid)
                        }
                    }.navigationTitle("오이 이야기").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { writing = false }.disabled(busy) } }
                        .interactiveDismissDisabled(busy)
                }
            }
    }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.utf16.count <= 40 &&
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.utf16.count <= 80 &&
        !story.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && story.utf16.count <= 2000
    }
    private func preview() { scene.updateDraft(height: height, heading: heading) }
    private func save() {
        guard let point = scene.draftPoint, let map = scene.data else { return }
        let coordinate = map.coordinate(point)
        let draft = frozenRequest ?? CampusSharedDraft(id: id, latitude: coordinate.latitude, longitude: coordinate.longitude,
                       heightMeters: height, headingDegrees: heading, displayName: name, title: title, story: story, revision: editing?.revision)
        busy = true; error = nil; frozenRequest = draft
        Task {
            defer { busy = false }
            do { try await store.save(draft); writing = false; scene.endPlacement() }
            catch {
                if case CampusSharedError.rejected = error { frozenRequest = nil }
                self.error = error.localizedDescription
            }
        }
    }
}

struct CampusSharedStoryView: View {
    let id: UUID
    let store: CampusSharedStore
    var onAR: ((CampusSharedOi) -> Void)?
    var onEdit: ((CampusSharedOi) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeletion = false
    @State private var deleting = false
    @State private var item: CampusSharedOi?
    @State private var error: String?
    @State private var requestID = UUID()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let item {
                    Text(item.statusLabel).font(.caption).foregroundStyle(.secondary)
                    Text(item.title).font(.largeTitle.bold())
                    Text(item.displayName).font(.headline)
                    Text(item.story).textSelection(.enabled)
                    Divider()
                    Text(String(format: "POSTECH · %.6f, %.6f", item.latitude, item.longitude)).font(.caption)
                    Text("이 이야기는 앱 운영진이 공개한 사용자 콘텐츠입니다. 학교 공식 납입 확인과는 별개예요.").font(.footnote).foregroundStyle(.secondary)
                    if item.status == "published", let onAR {
                        Button("현장에서 AR로 보기", systemImage: "arkit") { onAR(item) }.buttonStyle(.borderedProminent)
                    }
                    if store.authorized, store.mine.contains(where: { $0.id == item.id }), let onEdit {
                        HStack {
                            Button("위치·내용 수정", systemImage: "mappin.and.ellipse") { onEdit(item) }
                            Button("삭제", systemImage: "trash", role: .destructive) { confirmingDeletion = true }
                        }.buttonStyle(.bordered).disabled(deleting)
                        if let error { Text(error).foregroundStyle(.red) }
                    }
                } else if let error {
                    Text(error); Button("다시 확인") { requestID = UUID() }
                } else { ProgressView("이야기 확인 중") }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
        }.navigationTitle("오이 이야기").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(deleting)
            .confirmationDialog("이 오이와 이야기를 삭제할까요?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("오이와 이야기 삭제", role: .destructive) {
                    guard let item else { return }
                    deleting = true; error = nil
                    Task {
                        defer { deleting = false }
                        do { try await store.remove(item); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            } message: { Text("공유 지도에서 오이와 이야기가 삭제됩니다.") }
            .task(id: requestID) {
                item = nil; error = nil
                do { item = try await store.story(id) }
                catch is CancellationError { }
                catch { self.error = error.localizedDescription }
            }
    }
}

struct CampusSharedList: View {
    let store: CampusSharedStore
    let onAR: (CampusSharedOi) -> Void
    let onEdit: (CampusSharedOi) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var own = false
    @State private var error: String?
    @State private var deletion: CampusSharedOi?
    @State private var busy = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("오이 목록", selection: $own) {
                        Text("공개된 오이").tag(false); Text("내가 쓴 오이").tag(true)
                    }.pickerStyle(.segmented)
                    if let message = error ?? store.error { Text(message).foregroundStyle(.red) }
                    if let notice = store.notice { Text(notice).font(.footnote) }
                    if own && !store.authorized { Text("작성 코드를 등록하면 내 오이를 확인할 수 있어요.") }
                }
                ForEach(own ? store.mine : store.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        NavigationLink { CampusSharedStoryView(id: item.id, store: store, onAR: onAR, onEdit: onEdit) } label: {
                            VStack(alignment: .leading) { Text(item.title).font(.headline); Text("\(item.displayName) · \(item.statusLabel)").font(.caption) }
                        }
                        if own {
                            HStack {
                                Button("내용·위치 수정") { onEdit(item) }.buttonStyle(.bordered)
                                Button("삭제", role: .destructive) { deletion = item }.buttonStyle(.bordered)
                            }.disabled(busy)
                        }
                    }
                }
                if (own ? store.mine : store.items).isEmpty && !store.refreshing { Text(own ? "작성한 오이가 없어요." : "아직 공개된 오이가 없어요.") }
            }.refreshable { await store.refresh() }
                .navigationTitle("캠퍼스 오이").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } }
                    ToolbarItem(placement: .topBarLeading) { Button("새로고침") { Task { await store.refresh() } }.disabled(store.refreshing) }
                }
                .task { await store.refresh() }
                .confirmationDialog("이 오이와 이야기를 삭제할까요?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                    Button("삭제", role: .destructive) {
                        guard let item = deletion else { return }; busy = true
                        Task {
                            defer { busy = false; deletion = nil }
                            do { try await store.remove(item) }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                }
        }
    }
}
