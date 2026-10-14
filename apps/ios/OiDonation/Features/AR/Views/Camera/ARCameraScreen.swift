import SwiftUI
import ARKit
import AVFoundation

struct ARCameraScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = ARCameraViewModel()
    @State private var showSettings = false
    @State private var showAdjustments = false
    @State private var showPhotoSettings = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var controller = model.controller
        @Bindable var video = model.video
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let ratio = landscape ? 1 / controller.settings.photoRatio.portraitRatio : controller.settings.photoRatio.portraitRatio
            let previewHeight = min(max(1, geometry.size.height - 245), geometry.size.width / ratio)
            VStack(spacing: 0) {
                Color.clear.frame(height: 44).allowsHitTesting(false)
                Spacer(minLength: 0)
                Color.clear
                    .allowsHitTesting(false)
                    .frame(width: previewHeight * ratio, height: previewHeight)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        controller.photoViewport = $0
                    }
                    .overlay {
                        if let countdown = model.countdown {
                            Text("\(countdown)")
                                .font(.system(size: 72, weight: .bold)).foregroundStyle(.white)
                                .shadow(radius: 8).allowsHitTesting(false)
                                .accessibilityLabel("촬영까지 \(countdown)초")
                        }
                    }
                Spacer(minLength: 0)
                ARCaptureDock(model: model, showAdjustments: $showAdjustments, showSettings: $showSettings)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .environment(\.colorScheme, .dark)
                    // Keep the dock's layout space so the AR viewport never resizes.
                    .offset(y: (showAdjustments || showPhotoSettings) ? geometry.size.height : 0)
                    .opacity((showAdjustments || showPhotoSettings) ? 0 : 1)
                    .allowsHitTesting(!showAdjustments && !showPhotoSettings)
                    .accessibilityHidden(showAdjustments || showPhotoSettings)
            }
            .background {
                ZStack {
                    ARCameraPreview(controller: controller, recording: video.busy,
                                    topInset: max(44, controller.photoViewport.minY - geometry.frame(in: .global).minY) + geometry.safeAreaInsets.top)
                    VStack(spacing: 0) {
                        Color.black.opacity(controller.settings.opaquePhotoMargins ? 1 : 0.28)
                            .frame(height: geometry.safeAreaInsets.top + max(0, controller.photoViewport.minY - geometry.frame(in: .global).minY))
                        Color.clear.frame(height: previewHeight)
                        Color.black.opacity(controller.settings.opaquePhotoMargins ? 1 : 0.4)
                    }
                    .allowsHitTesting(false)
                }
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea()
            }
            .overlay(alignment: .top) {
                HStack(spacing: 22) {
                    Button { showPhotoSettings.toggle(); showAdjustments = false } label: {
                        Label(controller.settings.photoTimer == 0 ? "끔" : "\(controller.settings.photoTimer)초", systemImage: "timer")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }.accessibilityLabel("타이머 설정")
                    Button { showPhotoSettings.toggle(); showAdjustments = false } label: {
                        Text(controller.settings.photoRatio.rawValue)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }.accessibilityLabel("사진 비율 설정")
                    Button { showPhotoSettings.toggle(); showAdjustments = false } label: {
                        Image(systemName: "camera.filters")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }.accessibilityLabel("필터 설정")
                    Spacer(minLength: 0)
                    Button { Task { await model.close(); dismiss() } } label: {
                        Image(systemName: "xmark")
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.2), in: Circle())
                    }.accessibilityLabel("AR 카메라 닫기")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(height: max(44, controller.photoViewport.minY - geometry.frame(in: .global).minY))
                .disabled(video.busy || controller.capturing || model.countdown != nil)
            }
            .overlay(alignment: .bottom) {
                if showPhotoSettings {
                    ScrollView {
                        ARPhotoSettingsPanel(settings: $controller.settings, reselectBench: {
                            controller.selectBenchAgain()
                            showPhotoSettings = false
                        }) { showPhotoSettings = false }
                    }
                        .scrollIndicators(.hidden)
                        .defaultScrollAnchor(.bottom, for: .alignment)
                        .frame(maxHeight: min(520, max(0, geometry.size.height - 20)))
                        .padding(10)
                        .frame(maxWidth: 440)
                        .environment(\.colorScheme, .dark)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if showAdjustments {
                    let panelHeight = min(290, max(0, geometry.size.height - 20))
                    HStack {
                        if !landscape { Spacer(minLength: 0) }
                        ScrollView {
                            ARLiveAdjustmentPanel(controller: controller) {
                                showAdjustments = false
                            }
                            .frame(minHeight: panelHeight, alignment: .bottom)
                        }
                        .scrollIndicators(.hidden)
                        .frame(width: min(landscape ? 360 : 420, max(0, geometry.size.width - 20)),
                               height: panelHeight)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .environment(\.colorScheme, .dark)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showAdjustments)
            .animation(.easeInOut(duration: 0.25), value: showPhotoSettings)
            .onChange(of: controller.settings.photoRatio) { _, _ in model.viewportChanged() }
            .onChange(of: geometry.size) { _, _ in
                model.viewportChanged()
            }
        }
        .onDisappear { Task { await model.close() } }
        .background(.black)
        .statusBarHidden(true)
        .tint(.mint)
        .task { await controller.start() }
        .onChange(of: controller.settings) { old, _ in controller.update(from: old) }
        .onChange(of: controller.settings.background) { _, background in
            if background == .stadium { model.videoMode = false; showPhotoSettings = false }
        }
        .onChange(of: model.videoMode) { _, videoMode in
            if videoMode { controller.settings.background = .original }
        }
        .onChange(of: controller.settings.cameraExposure) { _, bias in
            guard let device = ARWorldTrackingConfiguration.configurableCaptureDeviceForPrimaryCamera else {
                controller.errorMessage = "이 기기에서는 카메라 노출 조절을 지원하지 않습니다."
                return
            }
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(min(device.maxExposureTargetBias, max(device.minExposureTargetBias, bias)))
                device.unlockForConfiguration()
            } catch { controller.errorMessage = "카메라 노출을 변경하지 못했습니다." }
        }
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
