//
//  CampusBuildingNotesView.swift
//  OiDonation
//
//  Created by Codex on 11/16/26.
//

import SwiftUI

struct CampusBuildingNotesView: View {
    let building: CampusBuildingTarget
    let remote: OiRemoteStore
    @State private var model: CampusBuildingNotesModel
    @State private var showingLogin = false
    @State private var reportedNote: CampusBuildingNote?
    @State private var deletingNote: CampusBuildingNote?
    @State private var sendTask: Task<Void, Never>?
    @FocusState private var composing: Bool
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let green = Color(red: 112/255, green: 140/255, blue: 64/255)
    private var visibleNotes: [CampusBuildingNote] { model.notes.filter { !OiContentSafetyStore.shared.isBlocked($0.authorId) } }
    private struct Context: Hashable { let owner: UUID?; let canWrite: Bool; let active: Bool }

    init(building: CampusBuildingTarget, remote: OiRemoteStore) {
        self.building = building; self.remote = remote
        _model = State(initialValue: CampusBuildingNotesModel(buildingID: building.id, service: remote))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(building.name).font(CampusStyle.medium(20)).tracking(0.4)
                .foregroundStyle(Color(white: 35/255)).lineLimit(2)
                .padding(.horizontal, 28).padding(.top, 20).padding(.bottom, 29)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("campus.notes.title")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if model.hasMore {
                            Button("이전 글 더 보기") { Task { await model.load(older: true) } }
                                .font(CampusStyle.body(12)).frame(maxWidth: .infinity, minHeight: 44).disabled(model.loading)
                        }
                        if model.loading && !model.hasLoaded { ProgressView("글을 불러오는 중").frame(maxWidth: .infinity).padding() }
                        if model.hasLoaded && visibleNotes.isEmpty {
                            Text("이 건물의 첫 이야기를 남겨 주세요.")
                                .font(CampusStyle.body(14)).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 150)
                        }
                        ForEach(visibleNotes) { note in
                            CampusBuildingNoteBubble(note: note, isOwn: note.authorId == remote.account?.id)
                                .id(note.id)
                                .contextMenu {
                                    if note.authorId == remote.account?.id {
                                        Button("글 삭제", systemImage: "trash", role: .destructive) { deletingNote = note }
                                    } else {
                                        Button("신고", systemImage: "flag") {
                                            if remote.canWriteBuildingNote { reportedNote = note }
                                            else { showingLogin = true }
                                        }
                                        Button("작성자 차단", systemImage: "person.crop.circle.badge.xmark") {
                                            OiContentSafetyStore.shared.setBlocked(note.authorId, name: note.authorLabel, blocked: true)
                                        }
                                    }
                                }
                                .accessibilityHint(note.authorId == remote.account?.id ? "내 글. 길게 눌러 삭제" : "길게 눌러 신고하거나 작성자 차단")
                        }
                        Color.clear.frame(height: 1).id("notes.bottom")
                    }.padding(.horizontal, 20).padding(.bottom, 12)
                }
                .scrollIndicators(.hidden).defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.top, for: .alignment)
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await model.load() }
                .onChange(of: model.sentID) { _, _ in
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo("notes.bottom", anchor: .bottom) }
                }
            }
            if let error = model.error {
                HStack {
                    Text(error).font(CampusStyle.body(12)).foregroundStyle(.secondary)
                    Button("다시 시도") { Task { await model.load() } }.font(CampusStyle.medium(12))
                }.padding(.horizontal, 24).padding(.bottom, 8).accessibilityIdentifier("campus.notes.error")
            }
            if let error = OiContentSafetyStore.shared.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            composer.padding(.horizontal, 20).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white, in: UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40))
        .tint(green)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("campus.notes.panel")
        .task(id: Context(owner: remote.account?.id, canWrite: remote.canWriteBuildingNote, active: phase == .active)) {
            model.resetForAccount()
            guard phase == .active else { return }
            await model.load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                // Refresh moderation/other people's notes while this building is visible.
                if !composing && !model.sending && !model.hasLoadedOlderNotes { await model.load() }
            }
        }
        .onDisappear { sendTask?.cancel(); model.invalidate() }
        .sheet(isPresented: $showingLogin) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 24) {
                    Text("로그인하고 짧은 글을 남겨 보세요.").font(CampusStyle.medium(20))
                    OiSignInView(remote: remote)
                    Spacer()
                }.padding(24).navigationTitle("로그인")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { showingLogin = false } } }
            }.presentationDetents([.medium, .large])
                .onChange(of: remote.canWriteBuildingNote) { _, signedIn in if signedIn { showingLogin = false } }
        }
        .sheet(item: $reportedNote) { note in
            CampusBuildingNoteReportView(note: note, remote: remote).id(remote.account?.id)
        }
        .confirmationDialog("이 글을 삭제할까요?", isPresented: Binding(get: { deletingNote != nil }, set: { if !$0 { deletingNote = nil } }), titleVisibility: .visible) {
            if let note = deletingNote {
                Button("삭제", role: .destructive) { sendTask = Task { await model.delete(note) }; deletingNote = nil }
            }
            Button("취소", role: .cancel) { deletingNote = nil }
        }
        .onChange(of: remote.account?.id) { _, _ in deletingNote = nil; reportedNote = nil }
    }

    @ViewBuilder private var composer: some View {
        if remote.canWriteBuildingNote {
            VStack(alignment: .trailing, spacing: 4) {
                Text("등록한 쪽지는 이 건물에 바로 공개돼요.")
                    .font(CampusStyle.body(11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) {
                    TextField("입력", text: $model.text, axis: .vertical)
                        .font(CampusStyle.semibold(18)).lineLimit(1...3).focused($composing)
                        .submitLabel(.send).onSubmit(send)
                        .accessibilityLabel("건물에 남길 짧은 글").accessibilityIdentifier("campus.notes.input")
                    Button(action: send) {
                        if model.sending { ProgressView().frame(width: 44, height: 44) }
                        else { Image(systemName: "arrow.up.message").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44) }
                    }.buttonStyle(.plain).disabled(!model.canSend)
                        .foregroundStyle(model.canSend ? green : Color.black.opacity(0.5))
                        .accessibilityLabel("글 등록").accessibilityIdentifier("campus.notes.send")
                }.padding(.leading, 22).padding(.trailing, 8).padding(.vertical, 6.5)
                    .background(Color(white: 248/255), in: RoundedRectangle(cornerRadius: 30))
                if composing || model.textCount > CampusBuildingNotesModel.textLimit {
                    Text("\(model.textCount)/\(CampusBuildingNotesModel.textLimit)")
                        .font(CampusStyle.body(10)).foregroundStyle(model.textCount > CampusBuildingNotesModel.textLimit ? .red : .secondary)
                        .padding(.trailing, 12)
                }
            }
        } else {
            Button { showingLogin = true } label: {
                HStack { Text("로그인하고 글 남기기").font(CampusStyle.semibold(16)); Spacer(); Image(systemName: "arrow.up.message") }
                    .foregroundStyle(.secondary).padding(.horizontal, 22).frame(height: 57)
                    .background(Color(white: 248/255), in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("campus.notes.login")
        }
    }

    private func send() {
        guard model.canSend else { return }
        sendTask = Task { await model.send() }
    }
}

struct CampusBuildingNoteBubble: View {
    let note: CampusBuildingNote
    let isOwn: Bool
    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 48) }
            VStack(alignment: isOwn ? .trailing : .leading, spacing: 5) {
                Text(note.authorLabel).font(CampusStyle.body(10))
                    .foregroundStyle(isOwn ? Color(red: 112/255, green: 140/255, blue: 64/255) : Color(white: 152/255))
                    .padding(.horizontal, 10)
                Text(note.body).font(CampusStyle.body(14)).foregroundStyle(Color(white: 35/255))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(isOwn ? Color(red: 234/255, green: 238/255, blue: 226/255) : Color(white: 243/255),
                                in: RoundedRectangle(cornerRadius: 10))
            }
            if !isOwn { Spacer(minLength: 48) }
        }.accessibilityElement(children: .combine)
    }
}

private struct CampusBuildingNoteReportView: View {
    let note: CampusBuildingNote
    let remote: OiRemoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var reason = "abuse"
    @State private var detail = ""
    @State private var busy = false
    @State private var notice: String?
    @State private var submitted = false
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section("신고할 글") { Text(note.body) }
                Section("신고 사유") {
                    Picker("사유", selection: $reason) {
                        Text("괴롭힘·혐오·모욕").tag("abuse"); Text("개인정보·권리 침해").tag("privacy")
                        Text("선정적인 내용").tag("sexual"); Text("폭력·위험한 내용").tag("violence"); Text("기타").tag("other")
                    }
                    TextField("추가 설명 (선택, 1,000자 이내)", text: $detail, axis: .vertical)
                    if let notice { Text(notice).font(.footnote) }
                    if busy { ProgressView() }
                    Button("신고 접수") { submit() }.disabled(busy || submitted || detail.unicodeScalars.count > 1000)
                }
                Text("신고 내용은 공개되지 않습니다. 운영자가 신고된 글을 검토하며, 위반 내용은 삭제됩니다.").font(.footnote)
            }.navigationTitle("건물 글 신고")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
                .onDisappear { task?.cancel() }
        }
    }
    private func submit() {
        guard let owner = remote.account?.id else { return }
        busy = true
        task = Task {
            defer { busy = false }
            do {
                _ = try await remote.reportBuildingNote(id: note.id, reason: reason, detail: detail)
                guard !Task.isCancelled, owner == remote.account?.id else { return }
                submitted = true; notice = "신고가 접수됐어요. 검토 후 처리합니다."
            } catch {
                guard !Task.isCancelled, owner == remote.account?.id else { return }
                notice = error.localizedDescription
            }
        }
    }
}
