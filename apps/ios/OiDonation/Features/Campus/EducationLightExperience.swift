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
    @State private var isVisible = false
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    @Environment(OiRemoteStore.self) private var remote: OiRemoteStore?

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
        .onAppear { isVisible = true; model.setActive(phase == .active); model.connectEducation(remote) }
        .onDisappear { isVisible = false; model.setActive(false) }
        .onChange(of: remote?.account?.id) { _, _ in model.educationSignInRequested = false; model.notifyEducationIdentity() }
        .onChange(of: remote?.needsReauthentication) { _, _ in model.notifyEducationIdentity() }
        .onChange(of: remote?.canStartStory) { _, _ in model.notifyEducationIdentity() }
        .onChange(of: remote?.isOperator) { _, _ in model.notifyEducationIdentity() }
        .sheet(isPresented: $model.educationSignInRequested) {
            if let remote {
                NavigationStack {
                    ScrollView { OiSignInView(remote: remote).padding(24) }
                        .navigationTitle("오이기부 로그인")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { model.educationSignInRequested = false } } }
                }
            }
        }
        .onChange(of: phase) { _, value in model.setActive(isVisible && value == .active) }
        .onChange(of: model.closeRequested) { _, requested in if requested { model.setActive(false); dismiss() } }
    }
}

@MainActor @Observable
final class EducationLightWebModel: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var loading = true
    var failure: String?
    var scattered = false
    var closeRequested = false
    var educationSignInRequested = false
    @ObservationIgnored private weak var educationRemote: OiRemoteStore?
    @ObservationIgnored let webView: WKWebView
    @ObservationIgnored let storySheetCloseButton = UIButton(configuration: .glass())
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
        storySheetCloseButton.configuration?.image = UIImage(systemName: "xmark")
        storySheetCloseButton.configuration?.preferredSymbolConfigurationForImage = .init(pointSize: 17, weight: .semibold)
        storySheetCloseButton.configuration?.cornerStyle = .capsule
        storySheetCloseButton.tintColor = .label
        storySheetCloseButton.overrideUserInterfaceStyle = .light
        storySheetCloseButton.accessibilityLabel = "닫기"
        storySheetCloseButton.accessibilityIdentifier = "education.story-sheet.close"
        storySheetCloseButton.isHidden = true
        storySheetCloseButton.addAction(UIAction { [weak self] _ in
            self?.webView.evaluateJavaScript("document.querySelector('#educationDialog')?.close()", completionHandler: nil)
        }, for: .touchUpInside)
        webView.addSubview(storySheetCloseButton)
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
        // Keep the web sheet's layout slot, but draw its close control with UIKit.
        // Observe only sheet changes, never the continuously updating 3D scene.
        let sheetControl = """
        (()=>{
          function connect(){
            const sheet=document.querySelector('#educationDialog'),close=sheet?.querySelector('.close-button');
            if(!close)return false;
            close.style.visibility='hidden';close.setAttribute('aria-hidden','true');close.tabIndex=-1;
            let pending=0;
            function update(){
              pending=0;const rect=close.getBoundingClientRect();
              window.webkit.messageHandlers.building.postMessage({kind:'storySheetControl',open:sheet.open,
                x:rect.x,y:rect.y,width:rect.width,height:rect.height,viewportWidth:innerWidth});
            }
            function schedule(){if(!pending)pending=requestAnimationFrame(()=>{pending=requestAnimationFrame(update);});}
            new MutationObserver(schedule).observe(sheet,{attributes:true,attributeFilter:['open']});
            const resize=new ResizeObserver(schedule);resize.observe(sheet);resize.observe(close);
            sheet.addEventListener('close',schedule);
            window.addEventListener('resize',schedule);
            window.addEventListener('education-sheet-layout',schedule);
            window.visualViewport?.addEventListener('resize',schedule);
            window.visualViewport?.addEventListener('scroll',schedule);
            schedule();return true;
          }
          if(!connect()){
            const observer=new MutationObserver(()=>{if(connect())observer.disconnect();});
            observer.observe(document.body,{childList:true,subtree:true});
          }
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: sheetControl, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        load()
    }

    func load() {
        loading = true
        failure = nil
        storySheetCloseButton.isHidden = true
        guard let url = Bundle.main.url(forResource: "education-district-experience", withExtension: "html") else {
            loading = false
            failure = "앱에 포함된 건물 파일을 찾을 수 없습니다."
            return
        }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func setActive(_ active: Bool) {
        self.active = active
        if !active { storySheetCloseButton.isHidden = true }
        webView.evaluateJavaScript("window.__nativePaused=\(active ? "false" : "true");window.setNativeActive?.(\(active ? "true" : "false"))", completionHandler: nil)
        if active {
            webView.evaluateJavaScript("window.dispatchEvent(new Event('education-feed-refresh'));window.dispatchEvent(new Event('education-sheet-layout'))", completionHandler: nil)
        }
    }

    func connectEducation(_ remote: OiRemoteStore?) {
        educationRemote = remote
        notifyEducationIdentity()
    }

    func notifyEducationIdentity() {
        guard active else { return }
        webView.evaluateJavaScript("window.dispatchEvent(new Event('education-auth-changed'))", completionHandler: nil)
    }

    private func educationMessage(_ body: [String: Any], message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, webView.url?.isFileURL == true,
              let id = body["id"] as? String, UUID(uuidString: id) != nil,
              let action = body["action"] as? String else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            var response: [String: Any]
            do {
                guard let remote = self.educationRemote else { throw OiServiceError.unavailable }
                let value: Any
                if action == "login" {
                    self.educationSignInRequested = true
                    value = ["requested": true]
                } else if action == "logout" {
                    await remote.signOut()
                    guard remote.account == nil else { throw OiServiceError.unavailable }
                    value = ["signedOut": true]
                } else {
                    value = try await remote.educationRequest(action, values: body)
                }
                response = ["ok": true, "data": value]
            } catch {
                response = ["ok": false, "error": error.localizedDescription]
            }
            guard self.webView.url?.isFileURL == true else { return }
            self.webView.callAsyncJavaScript("window.educationNativeReply?.(requestID, response)",
                arguments: ["requestID": id, "response": response], in: nil, in: .page, completionHandler: nil)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        if kind == "education" {
            educationMessage(body, message: message)
        } else if kind == "storySheetControl" {
            guard message.frameInfo.isMainFrame, webView.url?.isFileURL == true else { return }
            storySheetCloseButton.isHidden = true
            guard active, body["open"] as? Bool == true,
                  let x = body["x"] as? Double, let y = body["y"] as? Double,
                  let width = body["width"] as? Double, let height = body["height"] as? Double,
                  let viewportWidth = body["viewportWidth"] as? Double,
                  [x, y, width, height, viewportWidth].allSatisfy(\.isFinite),
                  viewportWidth > 0, width >= 44, height >= 44 else { return }
            let scale = webView.bounds.width / viewportWidth
            let frame = CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
            guard webView.bounds.contains(frame) else { return }
            storySheetCloseButton.frame = frame
            storySheetCloseButton.isHidden = false
            webView.bringSubviewToFront(storySheetCloseButton)
        } else if kind == "close" {
            closeRequested = true
        } else if kind == "appearance", let dark = body["dark"] as? Bool {
            scattered = dark
        } else if kind == "ready" {
            loading = false
            if body["webgl"] as? Bool != true { failure = "이 기기에서 3D 화면을 시작하지 못했습니다." }
            setActive(active)
            notifyEducationIdentity()
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
        storySheetCloseButton.isHidden = true
        loading = false
        failure = "앱에 포함된 화면을 열지 못했습니다. 다시 시도해 주세요."
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        storySheetCloseButton.isHidden = true
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
    func makeCoordinator() -> EducationLightWebModel { model }
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: EducationLightWebModel) {
        coordinator.setActive(false)
    }
}
