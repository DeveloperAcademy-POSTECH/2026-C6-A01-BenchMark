import SwiftUI

struct ARCaptureDock: View {
    @Bindable var model: ARCameraViewModel
    @Binding var showAdjustments: Bool
    @Binding var showSettings: Bool
    @State private var showCharacters = false
    private let selectionButtonSize: CGFloat = 50
    private var controller: ARSessionController { model.controller }
    private var video: ARVideoRecorder { model.video }
    private var videoMode: Bool { model.videoMode }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                characterButton
                Spacer(minLength: 0)
                ARCaptureModePicker(videoMode: $model.videoMode)
                    .disabled(video.busy || controller.capturing || model.countdown != nil)
                Spacer(minLength: 0)
                placementMenu
            }
            .overlay(alignment: .center) {
                // 촬영 영역이 움직이지 않도록 높이가 고정된 모드 선택 행에 녹화 상태를 표시합니다.
                if let start = video.startedAt {
                    Text(start, style: .timer)
                        .font(.caption2).monospacedDigit().foregroundStyle(.red)
                        .offset(y: 29)
                } else if video.busy {
                    ProgressView().controlSize(.mini).offset(y: 29)
                }
            }
            if !controller.ready {
                HStack {
                    Button("카메라 재시도") { Task { await controller.start() } }
                        .buttonStyle(.borderedProminent)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("권한 설정", destination: url).buttonStyle(.bordered)
                    }
                }.font(.caption)
            }

            HStack(spacing: 4) {
                Button { showAdjustments.toggle() } label: {
                    dockLabel("조명", symbol: "lightbulb")
                }
                .disabled(video.busy || model.countdown != nil)
                .foregroundStyle(showAdjustments ? Color.mint : Color.primary)
                .accessibilityLabel("캐릭터 조명 조절")
                .accessibilityValue(showAdjustments ? "열림" : "닫힘")

                Button { controller.locked.toggle() } label: {
                    dockLabel("잠금", symbol: controller.locked ? "lock.fill" : "lock.open")
                }
                .disabled(controller.usesGeographicPlacement || !controller.placed || controller.capturing || video.busy || model.countdown != nil)
                .accessibilityLabel("위치 잠금")
                .accessibilityValue(controller.locked ? "잠김" : "해제됨")

                Button {
                    if videoMode { showAdjustments = false }
                    model.capture()
                } label: {
                    ZStack {
                        Circle().stroke(.primary, lineWidth: 3).frame(width: 64, height: 64)
                        if video.state == .recording {
                            RoundedRectangle(cornerRadius: 6).fill(.red).frame(width: 28, height: 28)
                        } else {
                            Circle().fill(videoMode ? Color.red : Color.primary).frame(width: 52, height: 52)
                        }
                        if controller.capturing { ProgressView().tint(.mint) }
                        if let countdown = model.countdown { Text("\(countdown)").font(.title.bold()).foregroundStyle(.black) }
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityLabel(model.countdown != nil ? "타이머 촬영 취소" : video.state == .recording ? "녹화 정지" : (videoMode ? "영상 및 음성 녹화" : "AR 사진 촬영"))
                .disabled(video.state == .recording ? false : (video.busy || !controller.canCapture))
                .opacity(controller.canCapture || video.busy ? 1 : 0.4)

                Button { controller.resetPlacement() } label: {
                    dockLabel(controller.usesGeographicPlacement ? "위치 재확인" : "재배치", symbol: "arrow.counterclockwise")
                }.disabled(!controller.placed || controller.capturing || video.busy || model.countdown != nil)

                Button { showSettings = true } label: {
                    dockLabel("설정", symbol: "gearshape")
                }.accessibilityLabel("실험 설정").disabled(video.busy || model.countdown != nil)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

    }

    private var placementMenu: some View {
        Menu {
            Picker("배치 방식", selection: Binding(get: { controller.placementMode },
                set: { controller.settings.placementMode = $0 })) {
                ForEach(ARManualPlacementMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                        .disabled(mode == .location && !controller.canUseLocationMode)
                }
            }
            if !controller.motions.isEmpty {
                Section("애니메이션") {
                    ForEach(controller.motions) { motion in
                        Button(motion.title) { controller.playMotion(motion.id) }
                    }
                    if controller.selectedMotion != nil {
                        Button(controller.motionPlaying ? "일시정지" : "계속 재생") { controller.toggleMotion() }
                    }
                }
            }
        } label: {
            Image(systemName: controller.placementMode.symbol)
                .font(.system(size: 21))
                .frame(width: selectionButtonSize, height: selectionButtonSize)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15))
        }
        .accessibilityLabel("배치 방식 선택")
        .accessibilityValue(controller.placementMode.title)
        .accessibilityIdentifier("ar.camera.placementMode")
        .disabled(controller.loading || controller.capturing || video.busy || model.countdown != nil)
    }

    private var characterButton: some View {
    Button { showCharacters = true } label: {
        ARSelectedCharacterThumbnail(character: controller.settings.character, subject: controller.subject, size: 38)
        .frame(width: selectionButtonSize, height: selectionButtonSize)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
    .popover(isPresented: $showCharacters, arrowEdge: .bottom) {
        ARCharacterSelectionView(selection: Binding(get: { controller.settings.character }, set: { model.selectMascot($0) }),
            originalSubject: controller.originalSubject,
            isMascotSelected: controller.subject == nil,
            restoreOriginal: { model.restoreOriginalSubject() })
            .preferredColorScheme(.dark)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(24)
    }
    .accessibilityLabel("캐릭터 선택")
    .accessibilityValue(controller.subject?.title ?? controller.settings.character.title)
    .accessibilityIdentifier("ar.camera.characters")
    .disabled(controller.loading || controller.capturing || video.busy || model.countdown != nil)
    }

    private func dockLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 20))
            Text(title).font(.caption2)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
    }
}
