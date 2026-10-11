import SwiftUI

struct ARCameraScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = ARCameraViewModel()
    @State private var showSettings = false
    @State private var showAdjustments = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var controller = model.controller
        @Bindable var video = model.video
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: 0) {
                ARCameraPreview(controller: controller, recording: video.busy)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                let dockLayout = landscape
                    ? AnyLayout(HStackLayout(spacing: 10))
                    : AnyLayout(VStackLayout(spacing: 10))
                dockLayout {
                    if showAdjustments {
                        ARLiveAdjustmentPanel(controller: controller) {
                            showAdjustments = false
                        }
                        .frame(maxWidth: .infinity)
                    }
                    ARCaptureDock(model: model, showAdjustments: $showAdjustments, showSettings: $showSettings)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .environment(\.colorScheme, .dark)
            }
            .onChange(of: geometry.size) { _, _ in
                model.viewportChanged()
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { Task { await model.close(); dismiss() } } label: {
                Image(systemName: "xmark").padding(12).background(.ultraThinMaterial, in: Circle())
            }.accessibilityLabel("AR 카메라 닫기")
                .disabled(video.busy || controller.capturing).opacity(video.busy ? 0 : 1).padding()
        }
        .onDisappear { Task { await model.close() } }
        .background(.black)
        .tint(.mint)
        .task { await controller.start() }
        .onChange(of: controller.settings) { old, _ in controller.update(from: old) }
        .onChange(of: scenePhase) { _, phase in
            model.sceneChanged(to: phase)
        }
        .sheet(isPresented: $showSettings) {
            ARSettingsView(controller: controller)
                .preferredColorScheme(.dark)
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(28)
        }
        .onChange(of: video.busy) { _, busy in controller.videoRecording = busy }
        .onChange(of: controller.ready) { _, ready in
            model.sessionReadinessChanged(ready)
        }
        .onChange(of: video.errorMessage) { _, message in
            if let message { controller.errorMessage = message; video.errorMessage = nil }
        }
        .sheet(item: $video.result) { ARVideoResultView(result: $0) }
        .sheet(item: $controller.result) { ARPhotoResultView(result: $0) }
        .alert("안내", isPresented: Binding(get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })) {
            Button("확인", role: .cancel) { controller.errorMessage = nil }
        } message: { Text(controller.errorMessage ?? "") }
    }

}
