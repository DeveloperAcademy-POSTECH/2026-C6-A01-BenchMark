//
//  ScratchPostcardView.swift
//  OiDonationClip
//
//  Created by jiwon hong on 11/12/26.
//

import StoreKit
import SwiftUI

/// #291: scratch the card opened from an NFC postcard tag, then flip the revealed postcard.
///
/// Layout follows Figma "수집 시작 뷰"(5441:15795) and "수집 성공 뷰"(5400:14734). Content comes from the
/// published story linked to the tag. Saving records the story in the shared App Group collection, so the
/// full app shows it under "App Clip에서 수집한 카드" after install.
struct ScratchPostcardView: View {
    let postcard: ScratchPostcard
    var onClose: () -> Void
    let validateCollection: () async throws -> Bool

    private enum Phase { case scratching, revealing, revealed }
    private enum Toast: Equatable { case saved, failed(String) }

    static let brushRadius: CGFloat = 24
    static let revealThreshold = 0.6
    /// Only the inner card of the cover (Figma 296×436 at 33,33 in the 362×502 postcard, radius 30) can be scratched.
    static let scratchableArea = CGRect(x: 33.0 / 362, y: 33.0 / 502, width: 296.0 / 362, height: 436.0 / 502)
    static let scratchableCornerRadius: CGFloat = 30.0 / 362

    private static let green = Color(red: 112 / 255, green: 140 / 255, blue: 64 / 255)         // #708C40
    private static let barBackground = Color(red: 234 / 255, green: 238 / 255, blue: 226 / 255) // #EAEEE2
    private static let nameGreen = Color(red: 101 / 255, green: 128 / 255, blue: 78 / 255)      // #65804E
    private static let tagBrown = Color(red: 161 / 255, green: 92 / 255, blue: 3 / 255)         // #A15C03
    private static let hintGray = Color(red: 173 / 255, green: 173 / 255, blue: 173 / 255)      // #ADADAD

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collectionStore = StoryCollectionStore()
    @State private var phase: Phase = .scratching
    @State private var strokes: [[CGPoint]] = []
    @State private var lastPoint: CGPoint?
    @State private var coverage = ScratchCoverage(countedInset: 0.04)
    @State private var pendingFeedbackCells = 0
    @State private var scratchFeedback = 0
    @State private var revealFeedback = 0
    @State private var coverVisible = true
    @State private var effectStart: Date?
    @State private var flipAngle: Double = 0
    @State private var dragAngle: Double = 0
    @State private var hasFlipped = false
    @State private var showingFullAppOverlay = false
    @State private var toast: Toast?
    @State private var revealTask: Task<Void, Never>?
    @State private var toastTask: Task<Void, Never>?
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var safeAreaInsets = EdgeInsets()

    private var isRevealed: Bool { phase == .revealed }
    /// The success layout starts as soon as scratching completes, so the card moves while the effects play.
    private var showsSuccessLayout: Bool { phase != .scratching }
    private var isSaved: Bool { collectionStore.contains(storyID: postcard.story.storyID) }

    /// Postcard aspect ratio from Figma (362×502).
    static let cardAspectRatio: CGFloat = 362.0 / 502.0

    /// Screen layout computed from the device size and safe area.
    ///
    /// Values come from the Figma frames (402×874, 54pt status bar). On iPhone 17 Pro the result matches
    /// Figma exactly; on other devices fixed sizes and spacing are kept and only the postcard size changes.
    private struct Layout {
        static let sideInset: CGFloat = 20
        static let infoHeight: CGFloat = 84
        static let buttonHeight: CGFloat = 46
        static let characterSize = CGSize(width: 460.0 / 3, height: 588.0 / 3)
        /// Card frame bottom sits this far above the screen bottom on the start view (874 − 708):
        /// the character overlaps only the card's outer margin, never the scratch area.
        static let startBottomReserve: CGFloat = 166
        /// Space between the card and the action bar on the success view (781 − 728).
        static let hintAreaHeight: CGFloat = 53

        let size: CGSize
        let safeTop: CGFloat
        let safeBottom: CGFloat
        let isRevealed: Bool

        var contentWidth: CGFloat { max(size.width - Self.sideInset * 2, 1) }
        /// Figma places the back button 22.5pt below a 54pt status bar; devices report 8pt more (62).
        var topBarTop: CGFloat { max(safeTop - 8, 0) }
        var backButtonCenterY: CGFloat { topBarTop + 22.5 }
        var infoTop: CGFloat { topBarTop + (isRevealed ? 59 : 65) }
        /// Buttons end 27pt above the screen bottom on a 34pt home-indicator inset (Figma 847 vs 874).
        var barBottomPadding: CGFloat { max(safeBottom - 7, 16) }
        var barHeight: CGFloat { 20 + Self.buttonHeight + barBottomPadding }

        var cardFrame: CGRect {
            let top = infoTop + Self.infoHeight + (isRevealed ? 29 : 3)
            let bottomLimit = isRevealed
                ? size.height - barHeight - Self.hintAreaHeight
                : size.height - Self.startBottomReserve
            let width = max(min(contentWidth, (bottomLimit - top) * ScratchPostcardView.cardAspectRatio), 1)
            return CGRect(x: (size.width - width) / 2, y: top, width: width, height: width / ScratchPostcardView.cardAspectRatio)
        }
    }

    var body: some View {
        // Lays out the whole screen; safe area insets are measured separately because the full-screen
        // reader reports none.
        GeometryReader { proxy in
            let layout = Layout(
                size: proxy.size,
                safeTop: safeAreaInsets.top,
                safeBottom: safeAreaInsets.bottom,
                isRevealed: showsSuccessLayout
            )
            screen(layout)
                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .background {
            Color.clear
                .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeAreaInsets = $0 }
        }
        .background(Color.white.ignoresSafeArea())
        .animation(.spring(duration: 0.5), value: phase)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.4), trigger: scratchFeedback)
        .sensoryFeedback(.success, trigger: revealFeedback)
        .appStoreOverlay(isPresented: $showingFullAppOverlay) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
        .onDisappear {
            revealTask?.cancel()
            toastTask?.cancel()
            saveTask?.cancel()
        }
    }

    /// "수집 시작 뷰"(5441:15795) and "수집 성공 뷰"(5400:14734).
    private func screen(_ layout: Layout) -> some View {
        let cardFrame = layout.cardFrame
        return ZStack(alignment: .topLeading) {
            Color.white

            backButton
                .offset(x: Layout.sideInset, y: layout.backButtonCenterY - 22)

            infoCard(width: layout.contentWidth)
                .offset(x: Layout.sideInset, y: layout.infoTop)

            card(size: cardFrame.size)
                .frame(width: cardFrame.width, height: cardFrame.height)
                .offset(x: cardFrame.minX, y: cardFrame.minY)

            // Drawn above the card, as in Figma, so the stem overlaps the card margin.
            if phase == .scratching, let character = postcard.character {
                Image(uiImage: character)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Layout.characterSize.width, height: Layout.characterSize.height)
                    .offset(x: 13, y: layout.size.height - Layout.characterSize.height)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                Text("우표를 긁으면\n오이와 우표를 수집할 수 있어요!")
                    .font(.custom("Paperlogy-4Regular", size: 16))
                    .tracking(0.32)
                    .foregroundStyle(Self.green)
                    .fixedSize()
                    .frame(height: 60, alignment: .leading)
                    .offset(x: 145, y: layout.size.height - 90 - 30)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if showsSuccessLayout {
                Text("탭하거나 옆으로 밀어서 뒤집기")
                    .font(.custom("Paperlogy-4Regular", size: 12))
                    .tracking(0.24)
                    .foregroundStyle(Self.hintGray)
                    .fixedSize()
                    .frame(width: layout.size.width, height: 20)
                    .offset(y: cardFrame.maxY + 19 - 10)
                    .transition(.opacity)
                actionBar(layout)
                    .offset(y: layout.size.height - layout.barHeight)
                    .transition(.move(edge: .bottom))
            }

            toastView
                .frame(width: layout.size.width, height: 80)
                .offset(y: cardFrame.maxY - 90)
        }
    }

    // MARK: - Header

    private var backButton: some View {
        Button(action: onClose) {
            Image(systemName: "chevron.left")
                .font(.system(size: 24))
                .tracking(0.48)
                .foregroundStyle(.black)
                .frame(width: 39, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("뒤로")
    }

    /// Figma "오이 정보": 84pt tall with a 322×52 row at y 16. Both views share the row; the start view
    /// centres it (x 20) with a 1pt border, the success view aligns it leading (x 16) with a shadow.
    private func infoCard(width: CGFloat) -> some View {
        let rowWidth = min(322, width - 32)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(.white)
                .shadow(color: Color(red: 28 / 255, green: 55 / 255, blue: 0).opacity(showsSuccessLayout ? 0.25 : 0), radius: 3.5)
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Self.green, lineWidth: 1)
                .opacity(showsSuccessLayout ? 0 : 1)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(Text(postcard.nameParts.lead).foregroundStyle(.black))\(Text(postcard.nameParts.suffix).foregroundStyle(Self.nameGreen))")
                        .font(ScratchPostcardFont.cucumberName)
                        .tracking(1.56)
                        .minimumScaleFactor(0.5)
                        .frame(height: 33, alignment: .leading)
                    HStack(spacing: 6) {
                        ForEach(postcard.story.tags.filter { !$0.isEmpty }, id: \.self) { tag in
                            HStack(spacing: 1) {
                                Text("#").tracking(-0.52)
                                Text(tag).tracking(0.26)
                            }
                        }
                    }
                    .font(.custom("Paperlogy-4Regular", size: 13))
                    .foregroundStyle(Self.tagBrown)
                    .frame(height: 16)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("| \(postcard.donorLine)").frame(height: 12)
                    Text("| \(postcard.story.location.displayName)").frame(height: 12)
                    Text("| \(postcard.dateLine)").frame(height: 12)
                }
                .font(.custom("Paperlogy-4Regular", size: 10))
                .tracking(0.2)
                .foregroundStyle(.black)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
                .padding(.top, 2)
            }
            .lineLimit(1)
            .frame(width: rowWidth, height: 52, alignment: .topLeading)
            .offset(x: showsSuccessLayout ? 16 : (width - rowWidth) / 2, y: 16)
        }
        .frame(width: width, height: Layout.infoHeight)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Card

    private func card(size: CGSize) -> some View {
        FlipCard(angle: flipAngle + dragAngle) {
            frontFace
        } back: {
            if let back = postcard.back {
                Image(uiImage: back).resizable().scaledToFit()
            } else {
                ScratchPostcardFallbackBack(message: postcard.story.content, author: postcard.donorLine)
            }
        }
        .modifier(FlipPeekHint(isActive: isRevealed && !hasFlipped && !reduceMotion && dragAngle == 0))
        .overlay {
            ScratchSparkleBurst(startDate: effectStart)
                .frame(width: size.width * 1.4, height: size.height * 1.2)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .gesture(phase == .scratching ? scratchGesture(size: size) : nil)
        .gesture(isRevealed ? flipDragGesture(width: size.width) : nil)
        .simultaneousGesture(isRevealed ? TapGesture().onEnded { flip(by: 180) } : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityHint(phase == .scratching ? "엽서 열기 동작으로 카드를 한 번에 긁을 수 있어요" : "뒤집기 동작으로 다른 면을 볼 수 있어요")
        .accessibilityAction(named: phase == .scratching ? "엽서 열기" : "뒤집기") {
            if phase == .scratching { completeReveal() } else if isRevealed { flip(by: 180) }
        }
    }

    private var frontFace: some View {
        ZStack {
            if let front = postcard.front {
                Image(uiImage: front).resizable().scaledToFit()
            } else {
                ScratchPostcardFallbackFront(photo: postcard.coverPhoto)
            }
            if coverVisible {
                // Scratching uncovers the photo; the postcard front appears only once scratching is complete.
                ZStack {
                    ScratchCoverUnderlay(photo: postcard.coverPhoto ?? postcard.front)
                    ScratchCover(photo: postcard.coverPhoto ?? postcard.front)
                        .mask {
                            ScratchMask(strokes: strokes, brushRadius: Self.brushRadius,
                                        scratchableArea: Self.scratchableArea, cornerRadiusFraction: Self.scratchableCornerRadius)
                        }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
            ScratchShineSweep(startDate: effectStart)
                .mask { Rectangle() }
                .allowsHitTesting(false)
        }
    }

    private var cardAccessibilityLabel: String {
        if phase == .scratching { return "\(postcard.story.cucumberName) 엽서. 긁어서 열 수 있는 카드" }
        return FlipCard<EmptyView, EmptyView>.showsBack(flipAngle)
            ? "엽서 뒷면. \(postcard.story.content). 보낸 사람 \(postcard.donorLine)"
            : "\(postcard.story.cucumberName) 엽서 앞면"
    }

    // MARK: - Bottom

    /// Figma "하단 버튼": 20pt top padding, two 46pt buttons 12pt apart, 25pt top corners.
    private func actionBar(_ layout: Layout) -> some View {
        let topCorners = UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25)
        return HStack(spacing: 12) {
            Button {
                showingFullAppOverlay = true
            } label: {
                Text("이어서 기부하기")
                    .font(.custom("Paperlogy-5Medium", size: 16))
                    .tracking(0.32)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.buttonHeight)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
            }
            .accessibilityHint("전체 앱 설치 안내를 열어요")
            Button(action: save) {
                Label(isSaved ? "저장 완료" : "앨범에 저장하기", systemImage: "checkmark")
                    .labelStyle(SaveLabelStyle(showsIcon: isSaved))
                    .font(.custom("Paperlogy-6SemiBold", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.buttonHeight)
                    .background(Self.green.opacity(isSaved ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 20))
            }
            .disabled(isSaved || saving)
            .accessibilityHint("이 엽서를 수집했다는 기록을 이 기기에 남겨요. 전체 앱을 설치하면 도감에서 볼 수 있어요")
        }
        .buttonStyle(.plain)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, Layout.sideInset)
        .padding(.top, 20)
        .padding(.bottom, layout.barBottomPadding)
        .frame(width: layout.size.width, height: layout.barHeight, alignment: .top)
        .background {
            ZStack(alignment: .top) {
                topCorners.fill(.white.opacity(0.4))
                topCorners
                    .fill(Self.barBackground)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: -1)
            }
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Group {
                switch toast {
                case .saved:
                    Text("엽서를 저장했어요\n전체 앱을 설치하면 도감에서 다시 볼 수 있어요")
                case .failed(let message):
                    Text(message)
                }
            }
            .font(.custom("Paperlogy-5Medium", size: 14))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .accessibilityAddTraits(.isStaticText)
        }
    }

    // MARK: - Scratching

    private func scratchGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in scratch(at: value.location, size: size) }
            .onEnded { _ in lastPoint = nil }
    }

    private func scratch(at location: CGPoint, size: CGSize) {
        guard phase == .scratching, size.width > 0, size.height > 0 else { return }
        let area = Self.scratchableArea
        let areaRect = CGRect(x: area.minX * size.width, y: area.minY * size.height,
                              width: area.width * size.width, height: area.height * size.height)
        let areaPath = Path(roundedRect: areaRect, cornerRadius: Self.scratchableCornerRadius * size.width, style: .continuous)
        // Touches outside the inner card do nothing and end the current stroke.
        guard areaPath.contains(location) else {
            lastPoint = nil
            return
        }
        let point = CGPoint(x: location.x / size.width, y: location.y / size.height)
        // Coverage is measured over the scratchable card only.
        let local = { (p: CGPoint) in CGPoint(x: (p.x - area.minX) / area.width, y: (p.y - area.minY) / area.height) }
        let radius = CGVector(dx: Self.brushRadius / areaRect.width, dy: Self.brushRadius / areaRect.height)

        let added: Int
        if let lastPoint, !strokes.isEmpty {
            let moved = hypot((point.x - lastPoint.x) * size.width, (point.y - lastPoint.y) * size.height)
            guard moved >= 2 else { return }
            added = coverage.scratch(from: local(lastPoint), to: local(point), radius: radius)
            strokes[strokes.count - 1].append(point)
        } else {
            added = coverage.scratch(at: local(point), radius: radius)
            strokes.append([point])
        }
        lastPoint = point

        pendingFeedbackCells += added
        if pendingFeedbackCells >= 8 {
            pendingFeedbackCells = 0
            scratchFeedback += 1
        }
        if coverage.fraction >= Self.revealThreshold { completeReveal() }
    }

    private func completeReveal() {
        guard phase == .scratching else { return }
        phase = .revealing
        lastPoint = nil
        revealFeedback += 1
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.5)) { coverVisible = false }
        if !reduceMotion { effectStart = .now }

        revealTask?.cancel()
        revealTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.3 : 1.0))
            guard !Task.isCancelled else { return }
            phase = .revealed
            try? await Task.sleep(for: .seconds(ScratchSparkleBurst.duration))
            guard !Task.isCancelled else { return }
            effectStart = nil
        }
    }

    // MARK: - Flipping

    private func flipDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragAngle = min(max(value.translation.width / max(width, 1) * 180, -180), 180)
            }
            .onEnded { value in
                let predicted = value.predictedEndTranslation.width / max(width, 1) * 180
                let direction: Double = abs(predicted) > 70 ? (predicted > 0 ? 180 : -180) : 0
                withAnimation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0.2)) {
                    flipAngle += direction
                    dragAngle = 0
                    if direction != 0 { hasFlipped = true }
                }
            }
    }

    private func flip(by degrees: Double) {
        withAnimation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.2)) {
            flipAngle += degrees
            hasFlipped = true
        }
    }

    // MARK: - Saving

    private func save() {
        guard !saving, !isSaved else { return }
        saving = true
        saveTask = Task { @MainActor in
            defer { saving = false }
            do {
                guard try await validateCollection() else {
                    show(.failed("이 엽서는 더 이상 수집할 수 없어요. 닫고 태그를 다시 확인해 주세요."))
                    return
                }
                try Task.checkCancellation()
                if collectionStore.collect(postcard.card) { show(.saved) }
                else { show(.failed(collectionStore.persistenceError ?? "엽서를 저장하지 못했어요. 다시 시도해 주세요.")) }
            } catch is CancellationError {} catch {
                if !Task.isCancelled { show(.failed("공개 상태를 확인하지 못했어요. 인터넷 연결을 확인하고 다시 시도해 주세요.")) }
            }
        }
    }

    private func show(_ newToast: Toast) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = newToast }
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
    }
}

/// Fonts used by the postcard views.
enum ScratchPostcardFont {
    /// Figma uses REATIC Wide; the App Clip keeps Paperlogy to stay under the 15MB NFC size limit.
    static let cucumberName = Font.custom("Paperlogy-7Bold", size: 26)
}

/// Shows the checkmark only after the postcard has been saved.
private struct SaveLabelStyle: LabelStyle {
    let showsIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            if showsIcon { configuration.icon }
            configuration.title
        }
    }
}
