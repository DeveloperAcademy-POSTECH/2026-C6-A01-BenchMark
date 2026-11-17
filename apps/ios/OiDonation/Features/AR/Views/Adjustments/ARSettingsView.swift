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
                    Toggle("사람 가림", isOn: $controller.settings.peopleOcclusion).disabled(!controller.peopleSupported || controller.isPalmMode)
                    Toggle("공간 가림 · LiDAR", isOn: $controller.settings.sceneOcclusion).disabled(!controller.meshSupported || controller.isPalmMode)
                    if controller.isPalmMode { Text("손바닥 모드에서는 손을 가리지 않도록 가림 효과를 잠시 끕니다.").font(.caption) }
                    Text("사람 가림: \(controller.peopleSupported ? "지원" : "미지원") · LiDAR 메시: \(controller.meshSupported ? "지원" : "미지원")").font(.caption)
                }
                .listRowBackground(Color.black.opacity(0.22))
                Section("캐릭터 조절") {
                    if controller.isPalmMode {
                        Picker("손 추적 반응", selection: Binding(get: { controller.settings.palmResponse ?? .stable },
                            set: { controller.settings.palmResponse = $0 })) {
                            ForEach(ARPalmResponse.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text("빠른 추적은 손의 움직임을 바로 따르고, 안정 추적은 거리 흔들림을 줄입니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(controller.usesGeographicPlacement
                        ? "핀치로 화면에 보이는 크기를 조절할 수 있습니다. 위치는 지도에 저장된 좌표와 인식된 바닥을 따릅니다."
                        : controller.isPalmMode
                            ? "핀치로 2.5~20cm 크기를 조절하고, 캐릭터를 한 손가락으로 드래그해 손 위 위치를 보정하세요. 잠금은 손 추적을 멈추고 현재 공간 위치를 고정합니다."
                            : "바닥을 터치해 캐릭터를 놓은 뒤, 핀치로 크기를 조절하고 캐릭터를 한 손가락으로 드래그해 이동하세요.")
                }
                .listRowBackground(Color.black.opacity(0.22))
                Section("촬영 안내") {
                    Text(controller.usesGeographicPlacement
                        ? "오이를 저장한 장소 주변에서 바닥을 천천히 비춰 주세요. 위치와 바닥이 확인되면 터치 없이 나타나요. GPS 기반 근사 위치입니다."
                        : controller.isPalmMode
                            ? "밝은 곳에서 손바닥 전체를 후면 카메라에 펼쳐 보여 주세요. 손 크기로 추정하는 근사 위치이며 손등과 구분하지 않습니다."
                            : "밝은 그늘의 평평한 바닥에서 시작하세요. 바닥을 여러 각도에서 비춘 뒤 터치하여 배치합니다. 캐릭터와 사람은 비슷한 거리에 서 주세요.")
                    Text("촬영은 합성 화면 스냅샷입니다. JPG와 설정 JSON이 앱의 Documents/Experiments에 저장됩니다. 설정 데이터는 촬영 요청 직전 값이며 사진과 프레임 단위로 동기화되지 않습니다.").font(.caption)
                    Button("설정 기본값 복원") { controller.resetSettings() }
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
