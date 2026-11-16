//
//  EducationLightExperience.swift
//  OiDonation
//
//  Created by Codex on 2026/11/12.
//

import SwiftUI
import WebKit
import OSLog
import Observation

struct EducationLightExperience: View {
    @State private var model: EducationLightWebModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss

    @MainActor init(model: EducationLightWebModel? = nil) {
        _model = State(initialValue: model ?? EducationLightWebModel())
    }

    var body: some View {
        ZStack {
            Color(red: 213/255, green: 235/255, blue: 245/255).ignoresSafeArea()
            EducationLightWebView(model: model).ignoresSafeArea()
            if model.loading {
                VStack(spacing: 16) {
                    ProgressView("작은 빛으로 건물을 짓고 있어요")
                    Button("체험 닫기") { dismiss() }.frame(minHeight: 44)
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            if let failure = model.failure {
                VStack(spacing: 18) {
                    Image(systemName: "arrow.clockwise.circle").font(.largeTitle)
                    Text("건물을 다시 불러와 주세요").font(.headline)
                    Text(failure).font(.footnote).multilineTextAlignment(.center)
                    Button("다시 열기") { model.load() }.buttonStyle(.borderedProminent)
                    Button("체험 닫기") { dismiss() }.frame(minHeight: 44)
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .padding(24)
            }
        }
        .preferredColorScheme(model.scattered ? .dark : .light)
        .onChange(of: phase) { _, value in model.setActive(value == .active) }
        .onChange(of: model.closeRequested) { _, requested in if requested { dismiss() } }
    }
}

@MainActor @Observable
final class EducationLightWebModel: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var loading = true
    var failure: String?
    var scattered = false
    var closeRequested = false
    @ObservationIgnored let webView: WKWebView
    private var active = true
    private let logger = Logger(subsystem: "com.Spero.OiDonation.Education", category: "Building")

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()
        configuration.setURLSchemeHandler(EducationSurfaceURLSchemeHandler(), forURLScheme: "oi-education")
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        webView.isInspectable = true
        #endif
        configuration.userContentController.add(EducationWeakMessageHandler(self), name: "building")
        let reporting = """
        window.EDUCATION_GEOMETRY_URL = 'oi-education://bundle/surface.bin';
        window.__educationLoadErrors = [];
        window.addEventListener('error', event => {
          if (window.__educationLoadErrors.length < 5) window.__educationLoadErrors.push(String(event.message));
          window.webkit.messageHandlers.building.postMessage({kind:'error', message:String(event.message)});
        });
        window.addEventListener('unhandledrejection', event => {
          if (window.__educationLoadErrors.length < 5) window.__educationLoadErrors.push(String(event.reason));
          window.webkit.messageHandlers.building.postMessage({kind:'error', message:String(event.reason)});
        });
        """
        configuration.userContentController.addUserScript(WKUserScript(source: reporting, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        load()
    }

    func load() {
        loading = true
        failure = nil
        guard let url = Bundle.main.url(forResource: "education-district-experience", withExtension: "html") else {
            loading = false
            failure = "앱에 포함된 건물 파일을 찾을 수 없습니다."
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func setActive(_ active: Bool) {
        self.active = active
        webView.evaluateJavaScript("window.setNativeActive?.(\(active ? "true" : "false"))", completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        if kind == "close" {
            closeRequested = true
        } else if kind == "appearance", let dark = body["dark"] as? Bool {
            scattered = dark
        } else if kind == "ready" {
            loading = false
            if body["webgl"] as? Bool != true { failure = "이 기기에서 3D 화면을 시작하지 못했습니다." }
            setActive(active)
            logger.info("Building ready: \(String(describing: body), privacy: .public)")
        } else if kind == "error" {
            loading = false
            failure = "3D 화면을 불러오는 중 오류가 발생했습니다."
            logger.error("Building renderer error")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handle(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handle(error) }
    private func handle(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false
        failure = "앱에 포함된 화면을 열지 못했습니다. 다시 시도해 주세요."
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        failure = "메모리를 확보하기 위해 화면이 종료되었습니다. 다시 열면 저장한 이야기를 복원합니다."
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL { decisionHandler(.allow) }
        else if url.scheme == "oi-education", url.host == "bundle", url.path == "/" {
            decisionHandler(.cancel)
            load() // The web logo returns to the same file origin and saved demo.
        }
        else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated, url.scheme == "https" { UIApplication.shared.open(url) }
        }
    }
}

/// Resolve only reviewed, content-addressed public web assets. No app secrets or
/// arbitrary bundle paths can be requested through the web scheme.
struct EducationLightAssetCatalog: Decodable {
    struct Asset: Decodable {
        let resource: String
        let mime: String

        func bundleURL(in bundle: Bundle = .main) -> URL? {
            guard resource.hasPrefix("education-light-"),
                  !resource.contains("/"), !resource.contains("\\"),
                  !resource.contains("..") else { return nil }
            return bundle.url(forResource: resource, withExtension: nil)
        }
    }

    let revision: String
    let assets: [String: Asset]

    static func load(in bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "education-light-assets", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }

    func asset(for url: URL) -> Asset? {
        guard url.scheme == "oi-education", url.host == "bundle",
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        return assets[url.path]
    }
}

private final class EducationSurfaceURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private let catalog = try? EducationLightAssetCatalog.load()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              url.scheme == "oi-education", url.host == "bundle" else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let assetURL: URL?
        let mime: String
        if url.path == "/surface.bin" {
            // Preserve the older geometry route without changing the map asset.
            assetURL = Bundle.main.url(forResource: "education-district-points", withExtension: "bin")
            mime = "application/octet-stream"
        } else if let asset = catalog?.asset(for: url) {
            assetURL = asset.bundleURL()
            mime = asset.mime
        } else {
            assetURL = nil
            mime = "application/octet-stream"
        }
        guard let assetURL else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        do {
            let data = try Data(contentsOf: assetURL, options: .mappedIfSafe)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                "Content-Type": mime,
                "Content-Length": String(data.count),
                "Access-Control-Allow-Origin": "*",
                "Cache-Control": "no-store",
                "X-Content-Type-Options": "nosniff"
            ])!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

// WKUserContentController retains its handlers; this proxy avoids retaining the model.
private final class EducationWeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

private struct EducationLightWebView: UIViewRepresentable {
    let model: EducationLightWebModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
