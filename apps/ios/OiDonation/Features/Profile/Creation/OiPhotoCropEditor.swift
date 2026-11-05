import SwiftUI
import UIKit

/// Only the confirmed rectangle leaves this editor; cancelling never edits the photo.
struct OiPhotoCropEditor: View {
    let image: UIImage
    let apply: (CGRect) -> Void
    @State private var selection = OiPhotoCropSelection()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("모서리·가장자리를 드래그해 크기를 바꾸고\n격자 안쪽을 드래그해 위치를 옮겨주세요.")
                    .font(.subheadline).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                OiPhotoCropCanvas(image: image, selection: selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("자유 비율 · 선택한 영역만 저장돼요.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("전체 선택") { selection.viewport?.resetCrop() }
                    .buttonStyle(.bordered).accessibilityIdentifier("oi.crop.reset")
                    .padding(.bottom, 16)
            }
            .padding(.top, 16).background(Color.black)
            .navigationTitle("사진 자르기").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }.accessibilityIdentifier("oi.crop.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("적용") {
                        guard let rect = selection.viewport?.normalizedCropRect else { return }
                        apply(rect); dismiss()
                    }.fontWeight(.semibold).accessibilityIdentifier("oi.crop.apply")
                }
            }
        }.preferredColorScheme(.dark)
            .environment(\.colorScheme, .dark)
            .tint(.white)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

@MainActor private final class OiPhotoCropSelection {
    weak var viewport: OiPhotoCropViewport?
}

private struct OiPhotoCropCanvas: UIViewRepresentable {
    let image: UIImage
    let selection: OiPhotoCropSelection

    func makeUIView(context: Context) -> OiPhotoCropViewport {
        let view = OiPhotoCropViewport(image: image)
        selection.viewport = view
        return view
    }
    func updateUIView(_ uiView: OiPhotoCropViewport, context: Context) {}
}

/// Crop coordinates are in the fixed, aspect-fit photo's coordinate system, not the canvas.
enum OiPhotoCropGeometry {
    enum Handle: String, CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, move
        var changesLeft: Bool { [.topLeft, .left, .bottomLeft].contains(self) }
        var changesRight: Bool { [.topRight, .right, .bottomRight].contains(self) }
        var changesTop: Bool { [.topLeft, .top, .topRight].contains(self) }
        var changesBottom: Bool { [.bottomLeft, .bottom, .bottomRight].contains(self) }
        var label: String {
            switch self {
            case .topLeft: "왼쪽 위 모서리"
            case .top: "위쪽 가장자리"
            case .topRight: "오른쪽 위 모서리"
            case .right: "오른쪽 가장자리"
            case .bottomRight: "오른쪽 아래 모서리"
            case .bottom: "아래쪽 가장자리"
            case .bottomLeft: "왼쪽 아래 모서리"
            case .left: "왼쪽 가장자리"
            case .move: "선택 영역 이동"
            }
        }
        func point(in rect: CGRect) -> CGPoint {
            CGPoint(x: changesLeft ? rect.minX : changesRight ? rect.maxX : rect.midX,
                    y: changesTop ? rect.minY : changesBottom ? rect.maxY : rect.midY)
        }
    }

    static func adjusted(_ rect: CGRect, handle: Handle, translation: CGPoint, inside bounds: CGRect) -> CGRect {
        guard !bounds.isEmpty, translation.x.isFinite, translation.y.isFinite else { return rect }
        func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat { min(max(value, lower), upper) }
        if handle == .move {
            return CGRect(x: clamp(rect.minX + translation.x, bounds.minX, bounds.maxX - rect.width),
                          y: clamp(rect.minY + translation.y, bounds.minY, bounds.maxY - rect.height),
                          width: rect.width, height: rect.height)
        }
        let minWidth = min(44, rect.width, bounds.width), minHeight = min(44, rect.height, bounds.height)
        var left = rect.minX, right = rect.maxX, top = rect.minY, bottom = rect.maxY
        if handle.changesLeft { left = clamp(left + translation.x, bounds.minX, right - minWidth) }
        if handle.changesRight { right = clamp(right + translation.x, left + minWidth, bounds.maxX) }
        if handle.changesTop { top = clamp(top + translation.y, bounds.minY, bottom - minHeight) }
        if handle.changesBottom { bottom = clamp(bottom + translation.y, top + minHeight, bounds.maxY) }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
}

/// The photo stays fixed. Eight handles resize the grid independently; dragging inside moves it.
@MainActor final class OiPhotoCropViewport: UIView {
    typealias Handle = OiPhotoCropGeometry.Handle
    private let imageView: UIImageView
    private let shade = CAShapeLayer()
    private let grid = CAShapeLayer()
    private var handles: [Handle: OiPhotoCropHandleView] = [:]
    private var gestureStart: CGRect?
    private var activeHandle: Handle?
    private var laidOutSize = CGSize.zero
    private(set) var imageRect = CGRect.zero
    private(set) var cropRect = CGRect.zero
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(dragSelection(_:)))

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        clipsToBounds = true
        accessibilityIdentifier = "oi.crop.viewport"
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        shade.fillColor = UIColor.black.withAlphaComponent(0.58).cgColor
        shade.fillRule = .evenOdd
        grid.fillColor = UIColor.clear.cgColor
        grid.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
        grid.lineWidth = 1
        layer.addSublayer(shade); layer.addSublayer(grid)
        for handle in Handle.allCases where handle != .move {
            let view = OiPhotoCropHandleView(handle: handle)
            view.adjust = { [weak self] grow in
                guard let self else { return }
                let step: CGFloat = grow ? 8 : -8
                let delta = CGPoint(x: handle.changesLeft ? -step : handle.changesRight ? step : 0,
                                    y: handle.changesTop ? -step : handle.changesBottom ? step : 0)
                adjustSelection(handle: handle, translation: delta)
            }
            handles[handle] = view; addSubview(view)
        }
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, bounds.size != laidOutSize, let image = imageView.image else { return }
        let previous = normalizedCropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let available = bounds.insetBy(dx: min(24, bounds.width / 4), dy: min(24, bounds.height / 4))
        let scale = min(available.width / image.size.width, available.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        imageRect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        imageView.frame = imageRect
        cropRect = CGRect(x: imageRect.minX + previous.minX * size.width, y: imageRect.minY + previous.minY * size.height,
                          width: previous.width * size.width, height: previous.height * size.height)
        laidOutSize = bounds.size
        gestureStart = nil; activeHandle = nil
        drawSelection()
    }

    var normalizedCropRect: CGRect? {
        guard !imageRect.isEmpty, !cropRect.isEmpty else { return nil }
        return CGRect(x: (cropRect.minX - imageRect.minX) / imageRect.width,
                      y: (cropRect.minY - imageRect.minY) / imageRect.height,
                      width: cropRect.width / imageRect.width, height: cropRect.height / imageRect.height)
    }

    func resetCrop() { cropRect = imageRect; drawSelection() }

    func adjustSelection(handle: Handle, translation: CGPoint) {
        cropRect = OiPhotoCropGeometry.adjusted(cropRect, handle: handle, translation: translation, inside: imageRect)
        drawSelection()
    }

    @objc private func dragSelection(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let point = recognizer.location(in: self)
            let nearest = handles.keys.min { distance(point, $0.point(in: cropRect)) < distance(point, $1.point(in: cropRect)) }
            if let nearest, distance(point, nearest.point(in: cropRect)) <= 32 { activeHandle = nearest }
            else if abs(point.x - cropRect.minX) <= 22, point.y >= cropRect.minY, point.y <= cropRect.maxY { activeHandle = .left }
            else if abs(point.x - cropRect.maxX) <= 22, point.y >= cropRect.minY, point.y <= cropRect.maxY { activeHandle = .right }
            else if abs(point.y - cropRect.minY) <= 22, point.x >= cropRect.minX, point.x <= cropRect.maxX { activeHandle = .top }
            else if abs(point.y - cropRect.maxY) <= 22, point.x >= cropRect.minX, point.x <= cropRect.maxX { activeHandle = .bottom }
            else { activeHandle = cropRect.contains(point) ? .move : nil }
            gestureStart = cropRect
            recognizer.setTranslation(.zero, in: self)
        case .changed, .ended:
            if let start = gestureStart, let handle = activeHandle {
                cropRect = OiPhotoCropGeometry.adjusted(start, handle: handle, translation: recognizer.translation(in: self), inside: imageRect)
                drawSelection()
            }
            if recognizer.state == .ended { gestureStart = nil; activeHandle = nil }
        case .cancelled, .failed:
            if let start = gestureStart { cropRect = start; drawSelection() }
            gestureStart = nil; activeHandle = nil
        default: break
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func drawSelection() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let mask = UIBezierPath(rect: imageRect); mask.append(UIBezierPath(rect: cropRect))
        shade.path = mask.cgPath
        let lines = UIBezierPath(rect: cropRect)
        for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
            lines.move(to: CGPoint(x: cropRect.minX + cropRect.width * fraction, y: cropRect.minY))
            lines.addLine(to: CGPoint(x: cropRect.minX + cropRect.width * fraction, y: cropRect.maxY))
            lines.move(to: CGPoint(x: cropRect.minX, y: cropRect.minY + cropRect.height * fraction))
            lines.addLine(to: CGPoint(x: cropRect.maxX, y: cropRect.minY + cropRect.height * fraction))
        }
        grid.path = lines.cgPath
        for (handle, view) in handles {
            let point = handle.point(in: cropRect)
            view.frame = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
        }
        CATransaction.commit()
    }
}

@MainActor private final class OiPhotoCropHandleView: UIView {
    let handle: OiPhotoCropGeometry.Handle
    var adjust: ((Bool) -> Void)?
    init(handle: OiPhotoCropGeometry.Handle) {
        self.handle = handle
        super.init(frame: .zero)
        backgroundColor = .clear; isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = "자르기 \(handle.label)"
        accessibilityIdentifier = "oi.crop.handle.\(handle.rawValue)"
        accessibilityTraits = .adjustable
        accessibilityHint = "드래그하여 영역 크기 변경. 위로 쓸면 확대, 아래로 쓸면 축소."
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityIncrement() { adjust?(true) }
    override func accessibilityDecrement() { adjust?(false) }
    override func draw(_ rect: CGRect) {
        let path = UIBezierPath(); path.lineWidth = 4; path.lineCapStyle = .round
        let x: CGFloat = handle.changesLeft ? 1 : -1
        let y: CGFloat = handle.changesTop ? 1 : -1
        if (handle.changesLeft || handle.changesRight) && (handle.changesTop || handle.changesBottom) {
            path.move(to: CGPoint(x: 22, y: 22 + y * 14)); path.addLine(to: CGPoint(x: 22, y: 22))
            path.addLine(to: CGPoint(x: 22 + x * 14, y: 22))
        } else if handle.changesLeft || handle.changesRight {
            path.move(to: CGPoint(x: 22, y: 11)); path.addLine(to: CGPoint(x: 22, y: 33))
        } else {
            path.move(to: CGPoint(x: 11, y: 22)); path.addLine(to: CGPoint(x: 33, y: 22))
        }
        UIColor.white.setStroke(); path.stroke()
    }
}
