import SwiftUI

struct ARSettingsView: View {
    @Bindable var controller: ARSessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("카메라 화면") {
                    Toggle("촬영 영역 밖 배경을 검정색으로", isOn: $controller.settings.opaquePhotoMargins)
                    Text("켜면 비율 밖 영역이 완전 검정색으로, 끄면 카메라 영상 위에 옅은 검정색으로 표시됩니다. 저장 사진에는 영향을 주지 않습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.black.opacity(0.22))
                Section("환경과 가림") {
                    Toggle("사람 가림", isOn: $controller.settings.peopleOcclusion).disabled(!controller.peopleSupported)
                    Toggle("공간 가림 · LiDAR", isOn: $controller.settings.sceneOcclusion).disabled(!controller.meshSupported)
                    Text("사람 가림: \(controller.peopleSupported ? "지원" : "미지원") · LiDAR 메시: \(controller.meshSupported ? "지원" : "미지원")").font(.caption)
                }
                .listRowBackground(Color.black.opacity(0.22))
                Section("캐릭터 조절") {
                    Text("두 손가락을 벌리거나 모으면 크기가 바뀝니다. 캐릭터를 한 손가락으로 좌우로 드래그하면 회전하고 위아래로 드래그하면 바닥 기준 높이가 바뀝니다. 하단 조명 버튼에서는 강도·방향·환경 밝기를 조절할 수 있습니다.")
                }
                .listRowBackground(Color.black.opacity(0.22))
                Section("촬영 안내") {
                    Text("밝은 그늘의 평평한 바닥에서 시작하세요. 바닥을 여러 각도에서 비춘 뒤 터치하여 배치합니다. 캐릭터와 사람은 비슷한 거리에 서 주세요.")
                    Text("촬영은 합성 화면 스냅샷입니다. JPG와 설정 JSON이 앱의 Documents/Experiments에 저장됩니다. 설정 데이터는 촬영 요청 직전 값이며 사진과 프레임 단위로 동기화되지 않습니다.").font(.caption)
                    Button("설정 기본값 복원") { controller.settings = ARCaptureSettings() }
                    Button("캐릭터 다시 불러오기") { controller.loadCharacter() }
                }
                .listRowBackground(Color.black.opacity(0.22))
            }
            .scrollContentBackground(.hidden)
            .background(.clear)
            .navigationTitle("실험 설정")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
    }

}
