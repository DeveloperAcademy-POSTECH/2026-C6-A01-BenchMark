import SwiftUI

struct ContentView: View {
    @State private var model: AppClipViewModel
    @State private var invocation: URL?
    @State private var retry = UUID()
    @State private var character: ClipCharacter?

    init(configuration: ClipConfiguration, invocationURL: URL? = nil) {
        _model = State(initialValue: AppClipViewModel(configuration: configuration))
#if DEBUG
        _invocation = State(initialValue: invocationURL ?? ProcessInfo.processInfo.environment["OI_CLIP_TEST_URL"].flatMap(URL.init(string:)))
#else
        _invocation = State(initialValue: invocationURL)
#endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("오이기부").font(.title.bold()).foregroundStyle(.green)
                    switch model.state {
                    case .waiting:
                        ContentUnavailableView("벤치의 이야기를 만나보세요", systemImage: "wave.3.right",
                            description: Text("명패의 NFC를 터치하면 연결된 이야기가 열립니다."))
                    case .loading: ProgressView("이야기를 불러오는 중이에요")
                    case .failed(let message):
                        Text(message)
                        Button("다시 시도") { retry = UUID() }
                    case .ready:
                        if let story = model.story {
                            Text(story.title).font(.largeTitle.bold())
                            Text(story.donorDisplayName).foregroundStyle(.secondary)
                            ForEach(Array(story.images.enumerated()), id: \.offset) { _, asset in
                                ClipRemoteImage(asset: asset, client: model.client)
                            }
                            Text(story.body).font(.body).textSelection(.enabled)
                            if let ar = story.character {
                                Button { character = ar } label: {
                                    Label("\(ar.name)와 AR 사진 찍기", systemImage: "camera.fill")
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                }.buttonStyle(.borderedProminent).tint(.green)
                                Text("캐릭터는 선택한 뒤 다운로드합니다. 네트워크 상태에 따라 시간이 걸릴 수 있어요.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(24).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .task(id: "\(invocation?.absoluteString ?? "")-\(retry)") { await model.load(invocation) }
        .onOpenURL { open($0) }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { open($0.webpageURL) }
        .fullScreenCover(item: $character) { ar in ClipARScreen(character: ar, client: model.client) }
    }

    private func open(_ url: URL?) {
        character = nil
        invocation = url
        retry = UUID()
    }
}
