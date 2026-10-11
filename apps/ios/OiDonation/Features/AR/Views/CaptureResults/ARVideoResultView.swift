import AVKit
import SwiftUI

struct ARVideoResultView: View {
    let result: ARVideoResult
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var saving = false
    @State private var saved = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VideoPlayer(player: player).clipShape(RoundedRectangle(cornerRadius: 20))
                Button(saved ? "사진 앱에 저장됨" : "영상 저장") { Task { await save() } }
                    .buttonStyle(.borderedProminent).disabled(saving || saved)
                ShareLink("영상 공유", item: result.url)
                if let notice { Text(notice).font(.callout) }
            }
            .padding()
            .navigationTitle("녹화 결과")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
        .onAppear { player = AVPlayer(url: result.url) }
        .onDisappear { player?.pause(); player = nil }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await ARPhotoLibraryService().save(result.url, as: .video)
            saved = true
        } catch { notice = "저장 실패: \(error.localizedDescription)" }
    }
}
