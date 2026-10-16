import SwiftUI
import ARKit
import AVFoundation

struct ClipARScreen: View {
    let character: ClipCharacter
    let client: ClipContentClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var modelFile: URL?
    @State private var progress: Double?
    @State private var error: String?
    @State private var retry = UUID()
    @State private var camera = ClipCameraController()
    @State private var photo: ClipPhoto?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let modelFile {
                ClipARPreview(file: modelFile, height: character.heightMeters, controller: camera)
                    .ignoresSafeArea()
            }
            VStack(spacing: 16) {
                HStack {
                    Text(character.name).font(.headline)
                    Spacer()
                    Button("닫기", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly).accessibilityLabel("AR 카메라 닫기")
                }
                Spacer()
                if let error {
                    Text(error)
                    Button("다시 시도") { retry = UUID() }
                    if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                        Button("카메라 권한 설정 열기") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                } else if modelFile == nil {
                    ProgressView(value: progress).tint(.white)
                    Text("캐릭터를 다운로드하는 중이에요")
                } else {
                    Text(camera.message).font(.callout)
                    HStack(spacing: 36) {
                        Button("재배치", systemImage: "arrow.counterclockwise") { camera.resetPlacement() }
                        Button {
                            camera.capture { photo = ClipPhoto(image: $0) }
                        } label: {
                            Image(systemName: "circle.inset.filled").font(.system(size: 64))
                        }
                        .accessibilityLabel("AR 사진 촬영")
                        .disabled(!camera.canCapture || camera.capturing)
                    }
                }
            }
            .foregroundStyle(.white).padding(24)
        }
        .task(id: retry) {
            modelFile = nil; error = nil; progress = nil
            guard ARWorldTrackingConfiguration.isSupported else {
                error = "이 기기에서는 AR 촬영을 사용할 수 없어요. 이야기는 계속 읽을 수 있습니다."
                return
            }
            var authorized = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                authorized = await AVCaptureDevice.requestAccess(for: .video)
            }
            guard authorized else { error = "AR 촬영을 위해 카메라 접근을 허용해 주세요."; return }
            do {
                let file = try await client.asset(character.asset, model: true) { value in
                    Task { @MainActor in progress = value }
                }
                try Task.checkCancellation()
                modelFile = file
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
        .onChange(of: scenePhase) { _, phase in camera.setActive(phase == .active) }
        .onDisappear { camera.stop() }
        .sheet(item: $photo) { result in
            NavigationStack {
                VStack {
                    Image(uiImage: result.image).resizable().scaledToFit()
                    ShareLink(item: Image(uiImage: result.image),
                        preview: SharePreview("오이기부 AR 사진", image: Image(uiImage: result.image))) {
                        Label("사진 공유", systemImage: "square.and.arrow.up")
                    }.buttonStyle(.borderedProminent)
                    Text("사진은 서버로 전송하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                }.padding()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { photo = nil } } }
            }
        }
    }
}

private struct ClipPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}
