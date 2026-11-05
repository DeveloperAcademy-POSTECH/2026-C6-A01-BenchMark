import AVKit
import SwiftUI

struct ARVideoResultView: View {
    let result: ARVideoResult
    let discardRecovery: () throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var saving = false
    @State private var saved = false
    @State private var notice: String?
    @State private var confirmingDeletion = false

    private var recovering: Bool { result.kind == .recoveryOriginal }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VideoPlayer(player: player).clipShape(RoundedRectangle(cornerRadius: 20))
                if recovering {
                    Text("카메라 영역으로 자르지 못한 녹화 원본을 보관했습니다. 화면의 버튼·안내가 포함될 수 있으며 중단 시점에 따라 재생되지 않을 수 있습니다. 원본을 확인한 뒤 저장하거나 공유해 주세요. 완료로 닫아도 원본은 보관됩니다.")
                        .font(.callout)
                }
                Button(saved ? "사진 앱에 저장됨" : (recovering ? "원본을 사진 앱에 저장" : "영상 저장")) { Task { await save() } }
                    .buttonStyle(.borderedProminent).disabled(saving || saved)
                ShareLink(recovering ? "전체 화면 원본 공유" : "영상 공유", item: result.url)
                if recovering {
                    Button("복구 원본 삭제", role: .destructive) { confirmingDeletion = true }
                        .disabled(saving)
                }
                if let notice { Text(notice).font(.callout) }
            }
            .padding()
            .navigationTitle(recovering ? "녹화 원본 복구" : "녹화 결과")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
        }
        .onAppear { player = AVPlayer(url: result.url) }
        .onDisappear { player?.pause(); player = nil }
        .confirmationDialog("보관한 녹화 원본을 삭제할까요?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button("원본 삭제", role: .destructive) {
                do {
                    player?.pause()
                    try discardRecovery()
                    dismiss()
                } catch { notice = "원본을 삭제하지 못했습니다. 다시 시도해 주세요." }
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("저장하거나 공유하지 않은 원본은 복구할 수 없습니다.")
        }
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
