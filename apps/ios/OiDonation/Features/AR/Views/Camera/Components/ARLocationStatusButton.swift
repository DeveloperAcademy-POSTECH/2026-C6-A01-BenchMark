//
//  ARLocationStatusButton.swift
//  OiDonation
//
//  Created by Codex on 2026/11/17.
//

import SwiftUI

/// Keep location guidance in the toolbar; expand details only on request.
struct ARLocationStatusButton: View {
    let summary: String
    let notice: String
    let instruction: String
    let tracking: String
    let needsPermission: Bool
    @State private var showDetails = false

    var body: some View {
        Button { showDetails = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "location").font(.system(size: 10))
                Text(summary).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(.black.opacity(0.24), in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("위치 인식: " + summary)
        .accessibilityHint("위치 안내와 권한 설정 보기")
        .accessibilityIdentifier("ar.camera.locationStatus")
        .popover(isPresented: $showDetails) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("위치 인식 안내").font(.headline)
                    Spacer(minLength: 8)
                    Button { showDetails = false } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("위치 안내 닫기")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(notice.isEmpty ? "저장 위치를 확인하고 있어요." : notice)
                        Text(instruction).foregroundStyle(.secondary)
                        Label(tracking, systemImage: "viewfinder").foregroundStyle(.secondary)
                        if needsPermission, let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("위치 권한 설정", destination: url)
                                .buttonStyle(.bordered).frame(minHeight: 44)
                        }
                    }
                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            }
            .padding(16).frame(idealWidth: 290, maxWidth: 320)
            .preferredColorScheme(.dark).tint(.mint)
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.ultraThinMaterial)
            .presentationCornerRadius(20)
        }
    }
}

#Preview("위치 안내") {
    VStack(spacing: 20) {
        ARLocationStatusButton(summary: "약 120m 남음", notice: "저장 위치 25m 안으로 이동해 주세요.",
            instruction: "가까워지면 오이가 자동으로 나타나요.", tracking: "추적 정상", needsPermission: false)
        ARLocationStatusButton(summary: "위치 권한 필요", notice: "정확한 위치를 허용해 주세요.",
            instruction: "설정에서 위치 권한을 확인해 주세요.", tracking: "추적 정상", needsPermission: true)
    }
    .padding().background(.gray)
}
