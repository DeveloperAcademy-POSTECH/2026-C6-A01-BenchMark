import SwiftUI

struct ARView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = ARSessionController()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AR 캐릭터 사진").font(.headline)
                Spacer()
                Button("닫기", systemImage: "xmark") { dismiss() }
            }.padding()
            ZStack(alignment: .topLeading) {
                ARCameraView(controller: controller)
                VStack(alignment: .leading, spacing: 6) {
                    Text(controller.tracking)
                    Text(controller.message)
                    if controller.loading { ProgressView("캐릭터 로딩 중") }
                }.font(.caption).padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            controls
        }
        .background(Color.black).foregroundStyle(.white).preferredColorScheme(.dark)
        .task { await controller.start() }
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await controller.start() } }
            else { controller.pause() }
        }
        .onChange(of: controller.settings) { previous, _ in controller.update(from: previous) }
        .alert("AR 안내", isPresented: Binding(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })) {
            Button("확인") { controller.errorMessage = nil }
        } message: { Text(controller.errorMessage ?? "") }
    }

    private var controls: some View {
        @Bindable var controller = controller
        return VStack(spacing: 10) {
            HStack {
                Picker("캐릭터", selection: $controller.settings.character) {
                    ForEach(ARCharacter.allCases) { Text($0.title).tag($0) }
                }.disabled(controller.loading || controller.capturing)
                Spacer()
                Button(controller.locked ? "위치 잠금 해제" : "위치 잠금") { controller.locked.toggle() }
                    .disabled(!controller.placed)
                Button("재배치") { controller.resetPlacement() }
            }
            HStack {
                Text("키").frame(width: 35)
                Slider(value: $controller.settings.height, in: 0.2...2.5)
                Text(String(format: "%.1fm", controller.settings.height)).monospacedDigit()
            }
            HStack {
                Text("회전").frame(width: 35)
                Slider(value: $controller.settings.rotation, in: -180...180)
            }
            Text("주변 환경 조명이 자동 적용됩니다.").font(.caption).foregroundStyle(.secondary)
            if !controller.ready { Button("카메라 다시 시도") { Task { await controller.start() } } }
        }.padding().background(.ultraThinMaterial)
    }
}
