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
    let remote: OiRemoteStore
    @Environment(\.openURL) private var openURL

    private enum Source {
        case photo(PhotosPickerItem)
        case camera(Data)
        case file(URL)
    }

    private struct Selection: Identifiable {
        let id = UUID()
        let source: Source
        let owner: UUID
    }

    @State private var acknowledged = false
    @State private var importing = false
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var pickerOwner: UUID?
    @State private var requestingCamera = false
    @State private var showingCamera = false
    @State private var capturedPhoto: Data?
    @State private var cameraDenied = false
    @State private var selection: Selection?
    @State private var review: OiSavedSchoolEvidenceReview?
    @State private var historyError: String?
    @State private var error: String?

    var body: some View {
        List {
            if remote.account != nil {
                Section("학교 소속 증빙") {
                    Text("학생증 앞면, 재학증명서, 학교나 소속이 표시된 앱 프로필을 제출할 수 있어요. 학교명과 소속 표기는 남기고, 결제 카드번호·보안코드 등 소속 확인에 필요 없는 정보는 가려 주세요.")
                        .font(.footnote)
                    Toggle("선택한 증빙을 분석을 위해 OpenAI로 전송하는 데 동의합니다", isOn: $acknowledged)
                        .disabled(selection != nil)
                    Group {
                        Button("사진 보관함에서 선택", systemImage: "photo.on.rectangle") {
                            openPicker { pickingPhoto = true }
                        }
                        .accessibilityIdentifier("oi.schoolEvidence.photoLibrary")
                        Button("카메라로 촬영", systemImage: "camera") {
                            openPicker { requestingCamera = true }
                        }
                        Button("파일 앱에서 선택", systemImage: "folder") {
                            openPicker { importing = true }
                        }
                    }
                    .disabled(!acknowledged || selection != nil || requestingCamera)
                    Text("JPEG·PNG·PDF, 최대 10MB")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if selection != nil { ProgressView("학교 증빙 분석 중") }
                    if let error { Text(error).foregroundStyle(.red) }
                    if let historyError { Text(historyError).font(.footnote).foregroundStyle(.secondary) }
                }
                if let review {
                    Section("최근 증빙 판정") {
                        Text(review.summary.title)
                            .font(.headline)
                            .accessibilityIdentifier("oi.schoolEvidence.outcome")
                        Text(review.summary.detail)
                        Text(review.summary.nextStep).font(.subheadline)
                        Label("제출자 본인 일치 미확인", systemImage: "person.crop.circle.badge.questionmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let reference = review.summary.reference, reference.url.scheme == "https" {
                            Link(reference.title, destination: reference.url)
                        }
                        Text(review.reviewedAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("로그인해 주세요.")
            }
        }
        .navigationTitle("학교 인증")
        .navigationBarTitleDisplayMode(.inline)
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            submit(.photo(item))
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.jpeg, .png, .pdf]) { result in
            switch result {
            case .success(let url): submit(.file(url))
            case .failure: error = "파일을 선택하지 못했어요. 파일 앱에서 다시 선택해 주세요."
            }
        }
        .task(id: requestingCamera) {
            guard requestingCamera else { return }
            await openCamera()
        }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            if let capturedPhoto { submit(.camera(capturedPhoto)) }
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
            }
            .ignoresSafeArea()
        }
        .alert("카메라 접근이 필요해요", isPresented: $cameraDenied) {
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("설정에서 카메라 접근을 허용하거나 사진 보관함에서 증빙을 선택해 주세요.")
        }
        .task(id: selection?.id) {
            guard let selection else { return }
            await analyze(selection)
        }
        .onChange(of: remote.account?.id) { clear() }
        .task(id: remote.account?.id) {
            guard let owner = remote.account?.id else { return }
            await loadReview(owner: owner)
        }
    }

    private func openPicker(_ present: () -> Void) {
        guard acknowledged, selection == nil, let owner = remote.account?.id else { return }
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

    private func submit(_ source: Source) {
        guard acknowledged, selection == nil, let owner = pickerOwner, owner == remote.account?.id else { return }
        pickerOwner = nil
        acknowledged = false
        error = nil
        selection = Selection(source: source, owner: owner)
    }

    private func clear() {
        pickerOwner = nil
        photo = nil
        pickingPhoto = false
        importing = false
        requestingCamera = false
        showingCamera = false
        capturedPhoto = nil
        cameraDenied = false
        selection = nil
        review = nil
        historyError = nil
        error = nil
        acknowledged = false
    }

    private func analyze(_ input: Selection) async {
        defer { if selection?.id == input.id { selection = nil } }
        do {
            let (data, mime): (Data, String)
            switch input.source {
            case .photo(let item):
                guard let original = try await item.loadTransferable(type: Data.self) else {
                    throw OiServiceError.server("사진을 불러오지 못했어요. 사진 보관함에서 다시 선택해 주세요.")
                }
                data = try OiPhotoProcessor.prepare(original)
                mime = "image/jpeg"
            case .camera(let jpeg):
                data = try OiPhotoProcessor.prepare(jpeg)
                mime = "image/jpeg"
            case .file(let url):
                (data, mime) = try await Self.readFile(url)
            }
            guard !data.isEmpty, data.count <= 10 * 1024 * 1024 else {
                throw OiServiceError.server("10MB 이하의 증빙을 선택해 주세요.")
            }
            try Task.checkCancellation()
            guard selection?.id == input.id, remote.account?.id == input.owner else { return }
            let result = try await remote.reviewSchoolEvidence(data, contentType: mime)
            guard !Task.isCancelled, selection?.id == input.id else { return }
            guard let summary = result.summary else {
                throw OiServiceError.server("최신 증빙 판정을 불러오지 못했어요. 잠시 후 다시 시도해 주세요.")
            }
            let saved = OiSavedSchoolEvidenceReview(summary: summary, reviewedAt: .now)
            review = saved
            historyError = nil
            do {
                try await remote.saveSchoolEvidenceReview(saved, owner: input.owner)
            } catch {
                guard !Task.isCancelled, remote.account?.id == input.owner else { return }
                historyError = "이번 판정을 기기에 저장하지 못했어요."
            }
        } catch {
            guard !Task.isCancelled, selection?.id == input.id else { return }
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
