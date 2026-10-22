// Created by 이돈혁

import SwiftUI

struct NFCWriteView: View {
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isURLFocused: Bool
    @State private var invocationURL = ""
    @State private var writer = NFCWriter()

    private var validationMessage: String? {
        do {
            _ = try NFCWriteRequest(invocationURL)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("App Clip 링크 기록", systemImage: "wave.3.right")
                        .font(.title2.bold())
                        .foregroundStyle(Color("OiGreen"))
                    Text("App Clip 호출 링크를 NFC 태그에 담아요. 기록을 마친 태그를 iPhone으로 인식하면 등록된 App Clip을 열 수 있어요.")
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("App Clip 호출 URL").font(.headline)
                    TextField("등록된 HTTPS 링크 입력", text: $invocationURL, axis: .vertical)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isURLFocused)
                        .padding(16)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                        .disabled(writer.isRunning)
                        .accessibilityLabel("App Clip 호출 URL")
                    if !invocationURL.isEmpty, let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("App Store Connect 또는 기기의 로컬 경험에 등록한 링크를 입력해 주세요. 링크 기록만으로 App Clip 호출 설정이 완료되지는 않아요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("기록 방법").font(.headline)
                    Text("1. 쓰기 가능한 NDEF NFC 태그 하나를 준비해요.\n2. 아래 버튼을 누르고 iPhone 윗부분을 태그에 가까이 대세요.\n3. 기록과 확인이 끝날 때까지 태그를 움직이지 마세요.")
                        .font(.body).fixedSize(horizontal: false, vertical: true)
                    Text("태그의 기존 내용은 입력한 링크로 교체돼요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if !writer.isAvailable {
                    Label("이 기기에서는 NFC 기록을 지원하지 않아요. NFC를 지원하는 실제 iPhone에서 이용해 주세요.", systemImage: "iphone.slash")
                        .font(.subheadline)
                }

                status

                Button {
                    isURLFocused = false
                    writer.write(invocationURL)
                } label: {
                    Text("NFC 태그에 기록")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(validationMessage != nil || !writer.isAvailable || writer.isRunning)
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .tint(Color("OiGreen"))
        .navigationTitle("NFC")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: invocationURL) { writer.clearResult() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { writer.cancel() }
        }
        .onDisappear { writer.cancel() }
    }

    @ViewBuilder
    private var status: some View {
        switch writer.state {
        case .idle:
            EmptyView()
        case .working(let message):
            VStack(alignment: .leading, spacing: 12) {
                ProgressView(message)
                Button("기록 취소") { writer.cancel() }.frame(minHeight: 44)
            }
        case .succeeded(let url):
            VStack(alignment: .leading, spacing: 8) {
                Label("기록한 링크를 확인했어요", systemImage: "checkmark.circle.fill").font(.headline)
                Text(url.absoluteString).font(.footnote).textSelection(.enabled)
                Text("App Clip 호출은 앱이 설치되지 않은 iPhone에서 태그를 인식해 확인해 주세요.")
                    .font(.subheadline)
            }
            .accessibilityElement(children: .combine)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").accessibilityElement(children: .combine)
        case .cancelled(let message):
            Text(message)
        }
    }
}

#Preview { NavigationStack { NFCWriteView() } }
#Preview("Large Text") {
    NavigationStack { NFCWriteView() }.environment(\.dynamicTypeSize, .accessibility3)
}
