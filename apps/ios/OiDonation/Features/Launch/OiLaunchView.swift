import SwiftUI

struct OiLaunchView: View {
    let container: AppContainer
    @State private var showingIntro = true

    var body: some View {
        ZStack {
            RootTabView(container: container)
                .allowsHitTesting(!showingIntro)
                .accessibilityHidden(showingIntro)
            if showingIntro {
                OiSplashView {
                    withAnimation(.easeOut(duration: 0.8)) { showingIntro = false }
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .statusBarHidden(showingIntro)
    }
}

struct OiSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var logoPhase = false
    var previewLogoPhase: Bool? = nil
    var onComplete: () -> Void = {}
    private var isLogo: Bool { previewLogoPhase ?? logoPhase }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 402, geometry.size.height / 874)
            ZStack {
                Image("SplashBackground").resizable()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                canvas
                    .frame(width: 402, height: 874)
                    .scaleEffect(scale)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLogo ? "오이기부" : "오래 남는 이야기를 기부하다")
        .task {
            guard previewLogoPhase == nil else { return }
            do {
                try await Task.sleep(for: .seconds(0.5))
                if reduceMotion {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { logoPhase = true }
                } else {
                    withAnimation(.easeOut(duration: 0.8)) { logoPhase = true }
                }
                try await Task.sleep(for: .seconds(reduceMotion ? 0.5 : 1.1))
                try Task.checkCancellation()
                onComplete()
            } catch is CancellationError { }
            catch { }
        }
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            letter("SplashRae", x: 143.81, y: 302.42, width: 53.22, height: 52.38)
            letter("SplashNam", x: 201.85, y: 302.42, width: 53.82, height: 52.38)
            letter("SplashNeun", x: 260.47, y: 303.26, width: 50.94, height: 51.48)
            letter("SplashYa", x: 145.80, y: 392.42, width: 53.94, height: 52.20)
            letter("SplashGiGreen", x: 204.54, y: 392.42, width: 51.90, height: 52.20)
            letter("SplashReul", x: 261.23, y: 394.34, width: 50.94, height: 50.76)
            letter("SplashDa", x: 198.36, y: 482.42, width: 55.74, height: 52.38)
            letter("SplashHa", x: 258.92, y: 482.42, width: 54.66, height: 52.38)
            morph("SplashO", final: "SplashFinalO", start: CGRect(x: 90.12, y: 305.32, width: 48.42, height: 46.32), end: CGRect(x: 151, y: 417, width: 42.44, height: 40.60))
            morph("SplashI", final: "SplashFinalI", start: CGRect(x: 90, y: 393, width: 51.18, height: 52.20), end: CGRect(x: 198, y: 415, width: 44.86, height: 45.76))
            morph("SplashGi", final: "SplashFinalGi", start: CGRect(x: 88, y: 482, width: 51.90, height: 52.20), end: CGRect(x: 247, y: 415, width: 45.49, height: 45.76))
            morph("SplashBu", final: "SplashFinalBu", start: CGRect(x: 145, y: 486, width: 48.42, height: 49.32), end: CGRect(x: 297, y: 417, width: 42.44, height: 43.23))
            Image("SplashLogo").resizable().frame(width: 74.80, height: 64.398)
                .position(x: 102.40, y: 437.199)
                .opacity(isLogo ? 1 : 0)
        }
    }

    private func letter(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
        Image(name).resizable().frame(width: width, height: height)
            .position(x: x + width / 2, y: y + height / 2)
            .opacity(isLogo ? 0 : 1)
    }

    private func morph(_ name: String, final: String, start: CGRect, end: CGRect) -> some View {
        let rect = isLogo && !reduceMotion ? end : start
        return ZStack {
            Image(name).resizable().opacity(isLogo ? 0 : 1)
            Image(final).resizable().opacity(isLogo ? 1 : 0)
        }
        .frame(width: (isLogo ? end : rect).width, height: (isLogo ? end : rect).height)
        .position(x: (isLogo ? end : rect).midX, y: (isLogo ? end : rect).midY)
    }
}

#Preview("시작 문구") { OiSplashView(previewLogoPhase: false) }
#Preview("오이기부 로고") { OiSplashView(previewLogoPhase: true) }
