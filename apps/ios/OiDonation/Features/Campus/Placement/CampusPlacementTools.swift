// Created by 이돈혁

import SwiftUI

/// Shared by device examples and the server-backed story editor.
struct CampusPlacementTools: View {
    let scene: CampusExploreScene
    @State private var step = 0.1

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("위에서 보기", systemImage: "scope") { scene.focusPlacementFromAbove() }
                    .accessibilityIdentifier("placement.topDown")
                Spacer()
                Button("주변 보기", systemImage: "map") { scene.showPlacementSurroundings() }
                    .accessibilityIdentifier("placement.surroundings")
            }.buttonStyle(.bordered).font(.caption)
            HStack(spacing: 6) {
                Menu {
                    Picker("한 번에 이동할 거리", selection: $step) {
                        Text("10cm").tag(0.1)
                        Text("50cm").tag(0.5)
                        Text("1m").tag(1.0)
                    }
                } label: {
                    Text(step == 1 ? "1m씩 ▾" : "\(Int(step * 100))cm씩 ▾")
                        .font(.caption).frame(minHeight: 44)
                }.accessibilityLabel("미세 이동 간격")
                Spacer(minLength: 0)
                nudge("왼쪽", symbol: "arrow.left", right: -1, forward: 0)
                nudge("위쪽", symbol: "arrow.up", right: 0, forward: 1)
                nudge("아래쪽", symbol: "arrow.down", right: 0, forward: -1)
                nudge("오른쪽", symbol: "arrow.right", right: 1, forward: 0)
            }
            Text("십자 중심이 저장 위치 · 십자 길이 1m · 실제 축척")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .disabled(scene.draftPoint == nil)
        .tint(CampusStyle.green)
    }

    private func nudge(_ name: String, symbol: String, right: Float, forward: Float) -> some View {
        Button {
            scene.nudgePlacement(right: right, forward: forward, meters: step)
        } label: {
            Image(systemName: symbol).frame(width: 44, height: 44)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("화면 \(name)으로 이동")
        .accessibilityIdentifier("placement.nudge.\(symbol)")
    }
}

struct CampusPlacementDimensions: View {
    @Binding var height: Double
    @Binding var heading: Double

    var body: some View {
        DisclosureGroup {
            HStack {
                Text("키").frame(width: 34, alignment: .leading)
                Slider(value: $height, in: 0.4...2, step: 0.1).accessibilityLabel("실제 오이 높이")
            }
            HStack {
                Text("방향").frame(width: 34, alignment: .leading)
                Slider(value: $heading, in: 0...359, step: 1).accessibilityLabel("북쪽 기준 시계 방향")
            }
        } label: {
            Text("실제 키 \(height, specifier: "%.1f")m · 방향 \(Int(heading))°")
        }.font(.caption)
    }
}

#Preview("바닥 선택 전") {
    CampusPlacementTools(scene: CampusExploreScene()).padding()
}
