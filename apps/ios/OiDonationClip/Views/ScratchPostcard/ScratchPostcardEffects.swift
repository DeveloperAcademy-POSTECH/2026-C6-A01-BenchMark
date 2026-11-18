//
//  ScratchPostcardEffects.swift
//  OiDonationClip
//
//  Created by jiwon hong on 11/12/26.
//

import SwiftUI
import UIKit

/// Keeps device-tilt presentation outside the SwiftUI card's existing flip and scratch state.
struct ScratchPostcardMotionEffect<Content: View>: UIViewControllerRepresentable {
    let isEnabled: Bool
    let content: Content

    init(isEnabled: Bool, @ViewBuilder content: () -> Content) {
        self.isEnabled = isEnabled
        self.content = content()
    }

    func makeUIViewController(context: Context) -> ScratchPostcardMotionEffectController<Content> {
        ScratchPostcardMotionEffectController(content: content, isEnabled: isEnabled, environment: context.environment)
    }

    func updateUIViewController(_ controller: ScratchPostcardMotionEffectController<Content>, context: Context) {
        withTransaction(context.transaction) {
            controller.update(content: content, isEnabled: isEnabled, environment: context.environment)
        }
    }

    static func dismantleUIViewController(_ controller: ScratchPostcardMotionEffectController<Content>, coordinator: ()) {
        controller.stopMotionEffects()
    }
}

/// The hosting controller stays stable when the effect is enabled, paused, or disabled.
final class ScratchPostcardMotionEffectController<Content: View>: UIViewController {
    let motionView = ScratchPostcardMotionEffectView()
    private let hostingController: UIHostingController<AnyView>

    init(content: Content, isEnabled: Bool, environment: EnvironmentValues = EnvironmentValues()) {
        hostingController = UIHostingController(rootView: AnyView(content.environment(\.self, environment)))
        super.init(nibName: nil, bundle: nil)
        hostingController.safeAreaRegions = []
        motionView.setMotionEnabled(isEnabled)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }

    override func loadView() {
        let container = UIView()
        container.backgroundColor = .clear
        container.isOpaque = false
        view = container
        motionView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(motionView)
        NSLayoutConstraint.activate([
            motionView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            motionView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            motionView.topAnchor.constraint(equalTo: container.topAnchor),
            motionView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        addChild(hostingController)
        guard let hostedView = hostingController.view else { return }
        hostedView.backgroundColor = .clear
        hostedView.isOpaque = false
        hostedView.clipsToBounds = false
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        motionView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: motionView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: motionView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: motionView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: motionView.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    func update(content: Content, isEnabled: Bool, environment: EnvironmentValues = EnvironmentValues()) {
        // A new hosting root has its own environment; retain the caller's accessibility and display values.
        hostingController.rootView = AnyView(content.environment(\.self, environment))
        motionView.setMotionEnabled(isEnabled)
    }

    func stopMotionEffects() {
        motionView.stopMotionEffects()
    }
}

/// Isolates UIKit's declarative motion effects from the card's own transform.
final class ScratchPostcardMotionEffectView: UIView {
    static let maximumTiltRadians = CGFloat.pi / 45
    static let perspective: CGFloat = -1 / 800

    private var requestedMotion = false
    private let tiltEffect: UIMotionEffectGroup = {
        let horizontal = UIInterpolatingMotionEffect(keyPath: "layer.transform.rotation.y", type: .tiltAlongHorizontalAxis)
        horizontal.minimumRelativeValue = -ScratchPostcardMotionEffectView.maximumTiltRadians
        horizontal.maximumRelativeValue = ScratchPostcardMotionEffectView.maximumTiltRadians
        let vertical = UIInterpolatingMotionEffect(keyPath: "layer.transform.rotation.x", type: .tiltAlongVerticalAxis)
        vertical.minimumRelativeValue = ScratchPostcardMotionEffectView.maximumTiltRadians
        vertical.maximumRelativeValue = -ScratchPostcardMotionEffectView.maximumTiltRadians
        let group = UIMotionEffectGroup()
        group.motionEffects = [horizontal, vertical]
        return group
    }()

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { return nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        synchronizeMotionEffects()
    }

    func setMotionEnabled(_ enabled: Bool) {
        requestedMotion = enabled
        synchronizeMotionEffects()
    }

    func stopMotionEffects() {
        requestedMotion = false
        synchronizeMotionEffects()
    }

    private func synchronizeMotionEffects() {
        let shouldRun = requestedMotion && window != nil
        let isInstalled = motionEffects.contains { $0 === tiltEffect }
        if shouldRun {
            guard !isInstalled else { return }
            var transform = CATransform3DIdentity
            transform.m34 = Self.perspective
            layer.transform = transform
            addMotionEffect(tiltEffect)
        } else {
            guard isInstalled || !CATransform3DIsIdentity(layer.transform) else { return }
            UIView.performWithoutAnimation {
                if isInstalled { removeMotionEffect(tiltEffect) }
                layer.removeAllAnimations()
                layer.transform = CATransform3DIdentity
            }
        }
    }
}

/// Inverse brush mask: opaque everywhere except where the user has scratched inside `scratchableArea`.
struct ScratchMask: View {
    /// Strokes in normalized card coordinates.
    let strokes: [[CGPoint]]
    let brushRadius: CGFloat
    /// Normalized rect that can be scratched; strokes outside it leave the cover intact.
    var scratchableArea = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Corner radius of `scratchableArea` as a fraction of the card width.
    var cornerRadiusFraction: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let area = CGRect(x: scratchableArea.minX * size.width, y: scratchableArea.minY * size.height,
                              width: scratchableArea.width * size.width, height: scratchableArea.height * size.height)
            context.clip(to: Path(roundedRect: area, cornerRadius: cornerRadiusFraction * size.width, style: .continuous))
            context.blendMode = .destinationOut
            for stroke in strokes {
                let points = stroke.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
                guard let first = points.first else { continue }
                if points.count == 1 {
                    context.fill(Path(ellipseIn: CGRect(x: first.x - brushRadius, y: first.y - brushRadius,
                                                        width: brushRadius * 2, height: brushRadius * 2)),
                                 with: .color(.black))
                } else {
                    var path = Path()
                    path.addLines(points)
                    context.stroke(path, with: .color(.black),
                                   style: StrokeStyle(lineWidth: brushRadius * 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

/// One-shot sparkle burst played when the postcard is fully revealed.
struct ScratchSparkleBurst: View {
    /// Start time of the burst; `nil` draws nothing and stops the timeline.
    let startDate: Date?
    static let duration: TimeInterval = 1.4

    private struct Particle {
        let angle: Double
        let distance: CGFloat
        let size: CGFloat
        let spin: Double
        let color: Color
    }

    private static let particles: [Particle] = {
        let colors: [Color] = [
            Color(red: 0.90, green: 0.35, blue: 0.62),
            Color(red: 0.36, green: 0.72, blue: 0.30),
            Color(red: 1.0, green: 0.76, blue: 0.20),
            .white
        ]
        return (0..<30).map { index in
            let jitter = Double((index * 37) % 11) / 11
            return Particle(
                angle: Double(index) / 30 * 2 * .pi + jitter * 0.35,
                distance: 0.45 + CGFloat((index * 53) % 17) / 17 * 0.45,
                size: 10 + CGFloat((index * 29) % 7) * 2.2,
                spin: Double((index % 2 == 0) ? 1 : -1) * (1.5 + jitter * 2),
                color: colors[index % colors.count]
            )
        }
    }()

    var body: some View {
        if let startDate {
            TimelineView(.animation) { timeline in
                let progress = timeline.date.timeIntervalSince(startDate) / Self.duration
                Canvas { context, size in
                    guard progress >= 0, progress <= 1 else { return }
                    let eased = 1 - pow(1 - progress, 3)
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let reach = max(size.width, size.height) * 0.75
                    for particle in Self.particles {
                        let distance = particle.distance * reach * eased
                        let point = CGPoint(
                            x: center.x + cos(particle.angle) * distance,
                            y: center.y + sin(particle.angle) * distance + 60 * progress * progress
                        )
                        let scale = particle.size * (1 - progress * 0.6)
                        var star = context
                        star.opacity = 1 - pow(progress, 2)
                        star.translateBy(x: point.x, y: point.y)
                        star.rotate(by: .radians(particle.spin * progress * .pi))
                        star.addFilter(.shadow(color: .white.opacity(0.9), radius: 3))
                        star.fill(Self.starPath(radius: scale), with: .color(particle.color))
                    }
                }
            }
        }
    }

    /// Four-point twinkle star centered at the origin.
    private static func starPath(radius: CGFloat) -> Path {
        var path = Path()
        let inner = radius * 0.28
        for index in 0..<8 {
            let angle = Double(index) * .pi / 4 - .pi / 2
            let length = index.isMultiple(of: 2) ? radius : inner
            let point = CGPoint(x: cos(angle) * length, y: sin(angle) * length)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A light band that sweeps once across the card after the reveal.
struct ScratchShineSweep: View {
    let startDate: Date?
    static let duration: TimeInterval = 0.9

    var body: some View {
        if let startDate {
            TimelineView(.animation) { timeline in
                let progress = min(max(timeline.date.timeIntervalSince(startDate) / Self.duration, 0), 1)
                GeometryReader { proxy in
                    let width = proxy.size.width
                    LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: width * 0.45, height: proxy.size.height * 1.6)
                        .rotationEffect(.degrees(20))
                        .offset(x: -width * 0.6 + width * 1.7 * progress, y: -proxy.size.height * 0.3)
                        .opacity(progress >= 1 ? 0 : 1)
                }
            }
        }
    }
}

/// Repeatedly tilts the card a little to hint that it can be flipped.
struct FlipPeekHint: ViewModifier {
    let isActive: Bool
    /// One tilt per increment. The animator stays attached so toggling the hint never rebuilds the card,
    /// which made the revealed front blink once (#348).
    @State private var peeks = 0
    private static let cycle: Duration = .seconds(2.05)

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 0.0, trigger: peeks) { view, angle in
                view.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0, duration: 0.9)
                    CubicKeyframe(-26, duration: 0.35)
                    SpringKeyframe(0, duration: 0.8, spring: .bouncy)
                }
            }
            .task(id: isActive) {
                guard isActive else { return }
                while !Task.isCancelled {
                    peeks += 1
                    try? await Task.sleep(for: Self.cycle)
                }
            }
    }
}

/// Two-sided card whose visible face follows the animated rotation angle.
struct FlipCard<Front: View, Back: View>: View, Animatable {
    var angle: Double
    let front: Front
    let back: Back

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    init(angle: Double, @ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.angle = angle
        self.front = front()
        self.back = back()
    }

    static func showsBack(_ angle: Double) -> Bool {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        return normalized > 90 && normalized < 270
    }

    var body: some View {
        let showsBack = Self.showsBack(angle)
        ZStack {
            front.opacity(showsBack ? 0 : 1)
            back
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(showsBack ? 1 : 0)
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }
}
