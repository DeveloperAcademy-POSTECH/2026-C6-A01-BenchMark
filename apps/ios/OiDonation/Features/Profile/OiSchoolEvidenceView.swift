//
//  OiSchoolEvidenceView.swift
//  OiDonation
//
//  Created by 이돈혁 on 2026-11-04.
//

import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct OiSchoolEvidenceView: View {
    enum Affiliation: Hashable { case student, graduate }
    enum Document: Hashable { case studentID, enrollment, diploma, webmail }
    enum Step: Hashable {
        case profile, affiliation, document(Affiliation), attachment(Affiliation, Document)
    }

    let remote: OiRemoteStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @FocusState private var focusedField: Field?
    private enum Field { case school, department }
    private enum Source { case photo(PhotosPickerItem), camera(Data), file(URL) }
    private struct Selection: Identifiable {
        let id = UUID()
        let source: Source
        let owner: UUID
    }
    private struct Attachment: Identifiable {
        let id: UUID
        let owner: UUID
        let data: Data
        let contentType: String
        let name: String
    }
    private struct AnalysisRequest: Identifiable {
        let id = UUID()
        let attachment: Attachment
    }
    private struct ProfileSubmission: Identifiable {
        let id = UUID()
        let owner: UUID
        let schoolID: String
        let admissionYear: Int
        let department: String?
    }

    @State private var step: Step
    @State private var admissionYear: Int?
    @State private var schoolID: String?
    @State private var schoolQuery = ""
    @State private var department = ""
    @State private var skipsDepartment = false
    @State private var profileSubmission: ProfileSubmission?
    @State private var hydratedOwner: UUID?
    @State private var acknowledged = false
    @State private var choosingSource = false
    @State private var importing = false
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var pickerOwner: UUID?
    @State private var requestingCamera = false
    @State private var showingCamera = false
    @State private var capturedPhoto: Data?
    @State private var cameraDenied = false
    @State private var selection: Selection?
    @State private var attachment: Attachment?
    @State private var analysisRequest: AnalysisRequest?
    @State private var review: OiSavedSchoolEvidenceReview?
    @State private var historyError: String?
    @State private var error: String?

    init(remote: OiRemoteStore, initialStep: Step = .profile) {
        self.remote = remote
        _step = State(initialValue: initialStep)
    }

    private var currentYear: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.component(.year, from: .now)
    }
    private var cleanDepartment: String { department.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isProcessing: Bool { selection != nil || analysisRequest != nil || profileSubmission != nil }
    private var canSaveProfile: Bool {
        schoolID != nil && admissionYear != nil && (skipsDepartment || (!cleanDepartment.isEmpty && cleanDepartment.unicodeScalars.count <= 100))
            && remote.hasLoadedRemote && !remote.needsReauthentication
            && !remote.isBusy && !isProcessing
    }
    private var filteredSchools: [OiSchool] {
        let query = schoolQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return remote.schools.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if remote.account != nil {
                    OiConnectionStatus(remote: remote, showsInitialProgress: !remote.hasLoadedRemote)
                    switch step {
                    case .profile: profileForm
                    case .affiliation: affiliationChoices
                    case .document(let affiliation): documentChoices(affiliation)
                    case .attachment: attachmentForm
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("oi.schoolEvidence.error") }
                } else {
                    Text("로그인한 뒤 학교 인증을 시작해 주세요.")
                        .font(CampusStyle.body(16))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 17)
            .padding(.bottom, 20)
        }
        .background(Color.white.ignoresSafeArea()).foregroundStyle(.black)
        .buttonStyle(.plain)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomAction }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            OiSettingsHeader(title: "학교 인증", back: goBack, close: { clearTransient(); dismiss() })
        }
        .accessibilityAction(.escape, goBack)
        .confirmationDialog("첨부 방법 선택", isPresented: $choosingSource, titleVisibility: .visible) {
            Button("사진 보관함에서 선택") { openPicker { pickingPhoto = true } }
            Button("카메라로 촬영") { openPicker { requestingCamera = true } }
            Button("파일 앱에서 선택") { openPicker { importing = true } }
            Button("취소", role: .cancel) {}
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            prepare(.photo(item))
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.jpeg, .png, .pdf]) { result in
            switch result {
            case .success(let url): prepare(.file(url))
            case .failure(let failure):
                if !OiServiceFailure.isCancellation(failure) { error = "파일을 선택하지 못했어요. 파일 앱에서 다시 선택해 주세요." }
            }
        }
        .task(id: requestingCamera) {
            if requestingCamera { await openCamera() }
        }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            if let capturedPhoto { prepare(.camera(capturedPhoto)) }
            capturedPhoto = nil
        }) {
            SchoolEvidenceCamera { result in
                if let result {
                    switch result {
                    case .success(let data): capturedPhoto = data
                    case .failure: error = "촬영한 사진을 읽지 못했어요. 다시 촬영해 주세요."
                    }
                }
                showingCamera = false
            }.ignoresSafeArea()
        }
        .alert("카메라 접근이 필요해요", isPresented: $cameraDenied) {
            Button("설정 열기") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url) { accepted in
                    if !accepted { error = "설정을 열지 못했어요. iPhone 설정에서 카메라 접근을 확인해 주세요." }
                }
            }
            Button("취소", role: .cancel) {}
        } message: { Text("설정에서 카메라 접근을 허용하거나 사진 보관함이나 파일 앱에서 증빙을 선택해 주세요.") }
        .task(id: selection?.id) {
            if let selection { await prepareAttachment(selection) }
        }
        .task(id: analysisRequest?.id) {
            if let analysisRequest { await analyze(analysisRequest) }
        }
        .task(id: profileSubmission?.id) {
            if let profileSubmission { await saveProfile(profileSubmission) }
        }
        .onChange(of: remote.account?.id) { _, _ in
            clearTransient()
            hydratedOwner = nil
            admissionYear = nil
            schoolID = nil
            schoolQuery = ""
            department = ""
            skipsDepartment = false
            review = nil
            historyError = nil
            step = .profile
        }
        .task(id: remote.account?.id) {
            guard let owner = remote.account?.id else { return }
            if remote.hasLoadedRemote { hydrateProfile(owner: owner) }
            await loadReview(owner: owner)
        }
        .task(id: remote.hasLoadedRemote) {
            guard remote.hasLoadedRemote, let owner = remote.account?.id else { return }
            hydrateProfile(owner: owner)
        }
        .onDisappear {
            if !showingCamera && !pickingPhoto && !importing && !choosingSource { clearTransient() }
        }
    }

    private var profileForm: some View {
        VStack(alignment: .leading, spacing: 40) {
            fieldSection("입학 년도") {
                Menu {
                    Picker("입학 년도", selection: $admissionYear) {
                        Text("연도선택 (학번)").tag(Int?.none)
                        ForEach(Array((1900...currentYear).reversed()), id: \.self) { year in
                            Text(String(year)).tag(Optional(year))
                        }
                    }
                } label: {
                    fieldContainer {
                        Text(admissionYear.map(String.init) ?? "연도선택 (학번)")
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 16, weight: .light))
                    }
                }.accessibilityIdentifier("oi.schoolEvidence.admissionYear")
            }
            fieldSection("학교") {
                VStack(spacing: 4) {
                    fieldContainer {
                        TextField("학교 이름 검색", text: $schoolQuery)
                            .focused($focusedField, equals: .school)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: schoolQuery) { _, query in
                                if remote.schools.first(where: { $0.id == schoolID })?.name != query { schoolID = nil }
                            }
                        Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .light))
                    }
                    .accessibilityIdentifier("oi.schoolEvidence.schoolSearch")
                    if focusedField == .school {
                        if filteredSchools.isEmpty && remote.hasLoadedRemote {
                            Text("등록된 학교를 찾을 수 없어요.").font(.footnote).foregroundStyle(.secondary)
                        }
                        ForEach(filteredSchools) { school in
                            Button {
                                schoolID = school.id
                                schoolQuery = school.name
                                focusedField = nil
                            } label: {
                                Text(school.name).font(CampusStyle.body(16))
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 20).contentShape(Rectangle())
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack { sectionTitle("학과"); Spacer(minLength: 12); skipDepartmentButton }
                    VStack(alignment: .leading, spacing: 12) { sectionTitle("학과"); skipDepartmentButton }
                }
                fieldContainer {
                    TextField("학과 직접 입력", text: $department)
                        .focused($focusedField, equals: .department)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                        .disabled(skipsDepartment)
                }.accessibilityIdentifier("oi.schoolEvidence.department")
                if cleanDepartment.unicodeScalars.count > 100 { Text("학과는 100자 이내로 입력해 주세요.").font(.footnote).foregroundStyle(.red) }
            }
            VStack(spacing: 16) {
                Label("학과를 입력하지 않아도 괜찮아요", systemImage: "questionmark.circle.fill")
                    .font(.custom("Paperlogy-7Bold", size: 16, relativeTo: .body))
                    .foregroundStyle(Color(white: 118 / 255))
                Text("학과를 입력하지 않아도 앱을 사용할 수 있어요. 건너뛰기를 눌러주세요!")
                    .font(CampusStyle.body(12)).tracking(0.24)
                    .foregroundStyle(Color(white: 178 / 255)).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
        }
        .disabled(profileSubmission != nil)
    }

    private var skipDepartmentButton: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 5).stroke(.black, lineWidth: 1)
                .overlay { if skipsDepartment { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)) } }
                .frame(width: 20, height: 20)
            Text("건너뛰기").font(CampusStyle.medium(17))
        }
        .accessibilityHidden(true)
        .overlay {
            Button {
                skipsDepartment.toggle()
                if skipsDepartment { focusedField = nil }
            } label: {
                Color.clear.frame(minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("학과 입력 건너뛰기")
            .accessibilityValue(skipsDepartment ? "선택됨" : "선택 안 됨")
            .accessibilityAddTraits(skipsDepartment ? .isSelected : [])
        }
    }

    private var affiliationChoices: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("인증 방식 선택")
            choice("졸업생 인증", detail: "학생증 또는 졸업증명서를 첨부해주세요") { step = .document(.graduate) }
            choice("재학생 인증", detail: "학생증 또는 재학증명서를 첨부해주세요") { step = .document(.student) }
        }
    }

    private func documentChoices(_ affiliation: Affiliation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("인증 수단 선택")
            choice("학생증", detail: "학생증을 스캔∙촬영∙캡처 후 첨부하여 인증하기") { step = .attachment(affiliation, .studentID) }
            if affiliation == .graduate {
                choice("졸업 증명서", detail: "학교에서 발급해 준 졸업 증명서를 첨부하여 인증하기") { step = .attachment(affiliation, .diploma) }
                choice("학교 웹메일", detail: "학교에서 사용하는 웹메일 화면을 촬영∙캡처 후 첨부하여 인증하기") { step = .attachment(affiliation, .webmail) }
            } else {
                choice("재학 증명서", detail: "학교에서 발급해 준 재학 증명서를 첨부하여 인증") { step = .attachment(affiliation, .enrollment) }
            }
        }
    }

    private var attachmentForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("인증 자료 첨부")
            Button { choosingSource = true } label: {
                VStack(spacing: 4) {
                    Text(attachment?.name ?? "파일 첨부하기").font(CampusStyle.body(16)).tracking(0.32)
                        .lineLimit(2).multilineTextAlignment(.center)
                    Text("PNG, JPEG, PDF 파일만 가능")
                        .font(CampusStyle.body(12)).tracking(0.24).foregroundStyle(Color(white: 121 / 255))
                }
                .padding(20).frame(maxWidth: .infinity, minHeight: 148)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color(white: 243 / 255).shadow(.inner(color: .black.opacity(0.25), radius: 6))))
                .contentShape(RoundedRectangle(cornerRadius: 20))
            }
            .disabled(isProcessing || requestingCamera || remote.needsReauthentication)
            .accessibilityIdentifier("oi.schoolEvidence.attachment")
            if selection != nil { ProgressView("첨부 파일 읽는 중") }
            if attachment != nil {
                Text("최대 10MB. 학교명과 소속 표기는 남기고, 결제 카드번호·보안코드 등 불필요한 정보는 가려 주세요.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("선택한 증빙을 분석을 위해 OpenAI로 전송하는 데 동의합니다", isOn: $acknowledged)
                    .font(CampusStyle.body(14)).tint(CampusStyle.green)
                    .disabled(analysisRequest != nil)
                    .accessibilityIdentifier("oi.schoolEvidence.consent")
            }
            if analysisRequest != nil { ProgressView("학교 증빙 분석 중") }
            if let historyError { Text(historyError).font(.footnote).foregroundStyle(.secondary) }
            if let review { reviewSummary(review) }
        }
    }

    private func reviewSummary(_ review: OiSavedSchoolEvidenceReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("최근 증빙 판정").font(CampusStyle.medium(20)).accessibilityAddTraits(.isHeader)
            Text(review.summary.title).font(CampusStyle.semibold(18)).accessibilityIdentifier("oi.schoolEvidence.outcome")
            Text(review.summary.detail).font(CampusStyle.body(14))
            Text(review.summary.nextStep).font(CampusStyle.body(14))
            Label("제출자 본인 일치 미확인", systemImage: "person.crop.circle.badge.questionmark")
                .font(.footnote).foregroundStyle(.secondary)
            if let reference = review.summary.reference, reference.url.scheme == "https" { Link(reference.title, destination: reference.url) }
            Text(review.reviewedAt, format: .dateTime.year().month().day().hour().minute())
                .font(.footnote).foregroundStyle(.secondary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 243 / 255), in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private var bottomAction: some View {
        if remote.account != nil {
            switch step {
            case .profile:
                primaryButton(profileSubmission == nil ? "다음" : "학적정보 저장 중", disabled: !canSaveProfile) {
                    guard let owner = remote.account?.id, let schoolID, let admissionYear, canSaveProfile else { return }
                    focusedField = nil
                    error = nil
                    profileSubmission = ProfileSubmission(owner: owner, schoolID: schoolID, admissionYear: admissionYear,
                        department: skipsDepartment ? nil : cleanDepartment)
                }
            case .attachment:
                primaryButton(analysisRequest == nil ? "인증 요청하기" : "분석 중", disabled: attachment == nil || !acknowledged || isProcessing || remote.isBusy || remote.needsReauthentication) {
                    guard let attachment, attachment.owner == remote.account?.id, acknowledged else { return }
                    error = nil
                    analysisRequest = AnalysisRequest(attachment: attachment)
                }
            default: EmptyView()
            }
        }
    }

    private func primaryButton(_ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(CampusStyle.medium(17)).foregroundStyle(CampusStyle.green)
                .padding(.vertical, 20).frame(maxWidth: .infinity, minHeight: 57)
                .background(CampusStyle.mapSheet, in: RoundedRectangle(cornerRadius: 20))
        }
        .disabled(disabled)
        .padding(.horizontal, 20)
        .padding(.vertical, 0)
        .background(.white)
        .accessibilityIdentifier("oi.schoolEvidence.continue")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(CampusStyle.medium(20)).accessibilityAddTraits(.isHeader)
    }
    private func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) { sectionTitle(title); content() }
    }
    private func fieldContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .font(CampusStyle.body(16)).tracking(0.32).foregroundStyle(Color(white: 141 / 255))
            .padding(.horizontal, 20).padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Color(white: 247 / 255), in: RoundedRectangle(cornerRadius: 30))
    }
    private func choice(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(CampusStyle.body(16)).tracking(0.32)
                Text(detail).font(CampusStyle.body(12)).tracking(0.24).foregroundStyle(Color(white: 121 / 255))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(Color(white: 243 / 255), in: RoundedRectangle(cornerRadius: 20))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }.accessibilityIdentifier("oi.schoolEvidence.choice.\(title)")
    }

    private func hydrateProfile(owner: UUID) {
        guard hydratedOwner != owner else { return }
        hydratedOwner = owner
        admissionYear = remote.profile?.schoolAdmissionYear
        schoolID = remote.profile?.schoolId
        schoolQuery = remote.schools.first { $0.id == schoolID }?.name ?? ""
        department = remote.profile?.schoolDepartment ?? ""
        skipsDepartment = remote.profile?.schoolAdmissionYear != nil && department.isEmpty
    }

    private func saveProfile(_ input: ProfileSubmission) async {
        defer { if profileSubmission?.id == input.id { profileSubmission = nil } }
        guard remote.account?.id == input.owner, !Task.isCancelled else { return }
        await remote.updateSchoolProfile(schoolID: input.schoolID, admissionYear: input.admissionYear, department: input.department)
        guard !Task.isCancelled, profileSubmission?.id == input.id, remote.account?.id == input.owner else { return }
        guard remote.error == nil, remote.profile?.schoolId == input.schoolID,
              remote.profile?.schoolAdmissionYear == input.admissionYear, remote.profile?.schoolDepartment == input.department else {
            error = remote.error ?? "학적정보를 저장하지 못했어요. 다시 시도해 주세요."
            return
        }
        step = .affiliation
    }

    private func goBack() {
        clearTransient()
        switch step {
        case .profile: dismiss()
        case .affiliation: step = .profile
        case .document: step = .affiliation
        case .attachment(let affiliation, _): step = .document(affiliation)
        }
    }

    private func openPicker(_ present: () -> Void) {
        guard !isProcessing, let owner = remote.account?.id, !remote.needsReauthentication else { return }
        pickerOwner = owner
        error = nil
        present()
    }

    private func openCamera() async {
        defer { requestingCamera = false }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            error = "이 기기에서는 카메라를 사용할 수 없어요. 사진 보관함이나 파일 앱에서 선택해 주세요."
            return
        }
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard !Task.isCancelled, let pickerOwner, pickerOwner == remote.account?.id else { return }
        if allowed { showingCamera = true } else { cameraDenied = true }
    }

    private func prepare(_ source: Source) {
        guard !isProcessing, let owner = pickerOwner, owner == remote.account?.id else { return }
        pickerOwner = nil
        acknowledged = false
        attachment = nil
        review = nil
        error = nil
        selection = Selection(source: source, owner: owner)
    }

    private func clearTransient() {
        profileSubmission = nil
        analysisRequest = nil
        pickerOwner = nil
        photo = nil
        pickingPhoto = false
        importing = false
        requestingCamera = false
        showingCamera = false
        choosingSource = false
        capturedPhoto = nil
        cameraDenied = false
        selection = nil
        attachment = nil
        error = nil
        acknowledged = false
        focusedField = nil
    }

    private func prepareAttachment(_ input: Selection) async {
        defer { if selection?.id == input.id { selection = nil } }
        do {
            let (data, mime, name): (Data, String, String)
            switch input.source {
            case .photo(let item):
                guard let original = try await item.loadTransferable(type: Data.self) else {
                    throw OiServiceError.server("사진을 불러오지 못했어요. 사진 보관함에서 다시 선택해 주세요.")
                }
                data = try OiPhotoProcessor.prepare(original)
                mime = "image/jpeg"
                name = "선택한 사진"
            case .camera(let jpeg):
                data = try OiPhotoProcessor.prepare(jpeg)
                mime = "image/jpeg"
                name = "촬영한 사진"
            case .file(let url):
                (data, mime) = try await Self.readFile(url)
                name = url.lastPathComponent
            }
            guard !data.isEmpty, data.count <= 10 * 1024 * 1024 else { throw OiServiceError.server("10MB 이하의 증빙을 선택해 주세요.") }
            try Task.checkCancellation()
            guard selection?.id == input.id, remote.account?.id == input.owner else { return }
            attachment = Attachment(id: input.id, owner: input.owner, data: data, contentType: mime, name: name)
        } catch {
            guard !Task.isCancelled, selection?.id == input.id, remote.account?.id == input.owner else { return }
            self.error = (error as? OiServiceError)?.localizedDescription ?? "파일을 읽지 못했어요. 파일 형식과 크기를 확인한 뒤 다시 선택해 주세요."
        }
    }

    private func analyze(_ input: AnalysisRequest) async {
        defer {
            if analysisRequest?.id == input.id { analysisRequest = nil; acknowledged = false }
        }
        do {
            let attachment = input.attachment
            guard attachment.owner == remote.account?.id, !Task.isCancelled else { return }
            let result = try await remote.reviewSchoolEvidence(attachment.data, contentType: attachment.contentType)
            guard !Task.isCancelled, analysisRequest?.id == input.id, remote.account?.id == attachment.owner else { return }
            guard let summary = result.summary else { throw OiServiceError.server("최신 증빙 판정을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.") }
            let saved = OiSavedSchoolEvidenceReview(summary: summary, reviewedAt: .now)
            review = saved
            self.attachment = nil
            historyError = nil
            do { try await remote.saveSchoolEvidenceReview(saved, owner: attachment.owner) }
            catch {
                guard !Task.isCancelled, remote.account?.id == attachment.owner else { return }
                historyError = "이번 판정을 기기에 저장하지 못했어요."
            }
        } catch {
            guard !Task.isCancelled, analysisRequest?.id == input.id, remote.account?.id == input.attachment.owner else { return }
            self.error = (error as? OiServiceError)?.localizedDescription
                ?? "파일이나 분석 응답을 읽지 못했어요. 파일 형식과 네트워크를 확인한 뒤 다시 시도해 주세요."
        }
    }

    private func loadReview(owner: UUID) async {
        do {
            let saved = try await remote.localSchoolEvidenceReview(owner: owner)
            guard !Task.isCancelled, remote.account?.id == owner, review == nil else { return }
            review = saved
        } catch {
            guard !Task.isCancelled, remote.account?.id == owner, review == nil else { return }
            historyError = "기기에 저장된 판정을 읽지 못했어요."
        }
    }

    @concurrent
    private static func readFile(_ url: URL) async throws -> (Data, String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let maximum = 10 * 1024 * 1024
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
        let invalidFile = OiServiceError.server("JPEG·PNG·PDF 파일을 10MB 이하로 선택해 주세요.")
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximum,
              let mime = values.contentType?.preferredMIMEType,
              ["image/jpeg", "image/png", "application/pdf"].contains(mime) else { throw invalidFile }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var data = Data()
        while let chunk = try file.read(upToCount: min(64 * 1024, maximum + 1 - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            data.append(chunk)
            guard data.count <= maximum else { throw invalidFile }
        }
        guard !data.isEmpty else { throw invalidFile }
        return (data, mime)
    }
}

private struct SchoolEvidenceCamera: UIViewControllerRepresentable {
    let complete: (Result<Data, OiServiceError>?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(complete: complete) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let complete: (Result<Data, OiServiceError>?) -> Void

        init(complete: @escaping (Result<Data, OiServiceError>?) -> Void) {
            self.complete = complete
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            complete(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let jpeg = image.jpegData(compressionQuality: 0.9) else {
                complete(.failure(.invalidInput))
                return
            }
            complete(.success(jpeg))
        }
    }
}

#Preview("School · Reference", traits: .fixedLayout(width: 402, height: 874)) {
    NavigationStack { OiSchoolEvidenceView(remote: OiRemoteStore()) }
}

#Preview("School · Small", traits: .fixedLayout(width: 375, height: 667)) {
    NavigationStack { OiSchoolEvidenceView(remote: OiRemoteStore()) }
}

#Preview("School · Large", traits: .fixedLayout(width: 440, height: 956)) {
    NavigationStack { OiSchoolEvidenceView(remote: OiRemoteStore()) }
}
