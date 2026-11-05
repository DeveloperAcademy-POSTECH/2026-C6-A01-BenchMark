import SwiftUI
import UIKit

/// Standalone camera action; tab navigation is owned by the native TabView.
struct OiCameraButton: View {
    let onCamera: () -> Void

    var body: some View {
        Button(action: onCamera) {
            Image(systemName: "camera.fill")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 62, height: 62)
                .glassEffect(.regular.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AR 카메라 열기")
    }
}

/// Keeps TabView's native tab bar while reserving trailing space for an action.
/// Uses public controller/view APIs only; no search-tab role or private subviews.
struct OiNativeTabBarCameraPlacement: UIViewControllerRepresentable {
    let onCamera: () -> Void

    func makeUIViewController(context: Context) -> CameraPlacementController {
        CameraPlacementController(onCamera: onCamera)
    }

    func updateUIViewController(_ controller: CameraPlacementController, context: Context) {
        controller.camera.rootView = OiCameraButton(onCamera: onCamera)
        controller.scheduleLayout()
    }

    static func dismantleUIViewController(_ controller: CameraPlacementController, coordinator: ()) {
        controller.removeCamera()
    }
}

@MainActor
final class CameraPlacementController: UIViewController {
    let camera: UIHostingController<OiCameraButton>
    private weak var owner: UITabBarController?
    private var layoutScheduled = false
    private var originalFrame: CGRect?
    private var boundsObservation: NSKeyValueObservation?
    private var positionObservation: NSKeyValueObservation?

    init(onCamera: @escaping () -> Void) {
        camera = UIHostingController(rootView: OiCameraButton(onCamera: onCamera))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scheduleLayout()
    }

    func scheduleLayout() {
        guard !layoutScheduled else { return }
        layoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutScheduled = false
            self.layoutCamera()
        }
    }

    private func layoutCamera() {
        guard view.window != nil else { return }
        var root: UIViewController = self
        while let parent = root.parent { root = parent }
        guard let tabs = findTabs(in: root), !tabs.tabBar.isHidden else {
            camera.view.isHidden = true
            return
        }
        if owner !== tabs {
            removeCamera()
            owner = tabs
            tabs.addChild(camera)
            camera.view.backgroundColor = .clear
            tabs.view.addSubview(camera.view)
            camera.didMove(toParent: tabs)
            // UIKit can restore the full bar frame during tab interactions.
            // Observe public layer geometry so the reserved space survives them.
            boundsObservation = tabs.tabBar.layer.observe(\.bounds) { [weak self] _, _ in
                Task { @MainActor in self?.scheduleLayout() }
            }
            positionObservation = tabs.tabBar.layer.observe(\.position) { [weak self] _, _ in
                Task { @MainActor in self?.scheduleLayout() }
            }
        }
        let bar = tabs.tabBar
        guard let parent = bar.superview else { return }
        let width = parent.bounds.width
        let buttonSize: CGFloat = 62
        let trailing: CGFloat = 20
        let gap: CGFloat = 12
        let reservedWidth = buttonSize + gap + trailing
        var frame = bar.frame
        // UIKit owns the vertical position; only reserve horizontal action space.
        frame.origin.x = 0
        frame.size.width = max(0, width - reservedWidth)
        originalFrame = CGRect(x: 0, y: frame.minY, width: width, height: frame.height)
        if bar.frame != frame { bar.frame = frame }
        let barInOwner = parent.convert(frame, to: tabs.view)
        let visibleHeight = max(buttonSize, frame.height - parent.safeAreaInsets.bottom)
        camera.view.frame = CGRect(
            x: tabs.view.bounds.width - trailing - buttonSize,
            y: barInOwner.minY + (visibleHeight - buttonSize) / 2,
            width: buttonSize, height: buttonSize
        )
        camera.view.isHidden = false
        tabs.view.bringSubviewToFront(camera.view)
    }

    private func findTabs(in controller: UIViewController) -> UITabBarController? {
        if let tabs = controller as? UITabBarController { return tabs }
        for child in controller.children {
            if let tabs = findTabs(in: child) { return tabs }
        }
        return nil
    }

    func removeCamera() {
        boundsObservation = nil
        positionObservation = nil
        if camera.parent != nil {
            camera.willMove(toParent: nil)
            camera.view.removeFromSuperview()
            camera.removeFromParent()
        }
        if let frame = originalFrame { owner?.tabBar.frame = frame }
        owner = nil
        originalFrame = nil
    }
}
