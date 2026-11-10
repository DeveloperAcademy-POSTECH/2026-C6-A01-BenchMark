//
//  OiSeedCucumberTouchSurface.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/9/26.
//

import SwiftUI
import UIKit

struct OiSeedCucumberTouchSurface: UIViewRepresentable {
    @Binding var appearance: OiSeedCucumberAppearance
    @Binding var selection: OiSeedCucumberPart

    func makeCoordinator() -> Coordinator { Coordinator(surface: self) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let coordinator = context.coordinator
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = coordinator
        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinch(_:)))
        pinch.delegate = coordinator
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: pan)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.surface = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var surface: OiSeedCucumberTouchSurface
        private var drag: (part: OiSeedCucumberPart, face: OiSeedCucumberAppearance.Face, tip: CGPoint)?
        private var resize: (part: OiSeedCucumberPart, size: CGFloat)?

        init(surface: OiSeedCucumberTouchSurface) { self.surface = surface }

        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            gesture.view === other.view
                && ((gesture is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
                    || (gesture is UIPinchGestureRecognizer && other is UIPanGestureRecognizer))
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view, let part = hit(gesture.location(in: view), in: view) else { return }
            surface.selection = part
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            if gesture.state == .began {
                let location = gesture.location(in: view)
                let start = CGPoint(x: location.x - translation.x, y: location.y - translation.y)
                drag = hit(start, in: view).map { part in
                    surface.selection = part
                    return (part, surface.appearance[part], surface.appearance.stemTip)
                }
            }
            if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
                defer { drag = nil }
                if gesture.state == .ended { move(by: translation, in: view) }
            } else {
                move(by: translation, in: view)
            }
        }

        private func move(by translation: CGPoint, in view: UIView) {
            let scale = OiSeedCucumberViewport(size: view.bounds.size).scale
            guard let drag, scale > 0 else { return }
            let dx = translation.x / scale
            let dy = translation.y / scale
            var appearance = surface.appearance
            if drag.part == .stem {
                appearance.moveStemTip(to: CGPoint(x: drag.tip.x + dx, y: drag.tip.y + dy))
            } else {
                var face = appearance[drag.part]
                face.x = drag.face.x + dx / appearance.bodyWidth
                face.y = drag.face.y + dy / appearance.bodyHeight
                appearance[drag.part] = face
            }
            surface.appearance = appearance
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                let part = surface.selection
                guard OiSeedCucumberPart.faceParts.contains(part) else { return }
                resize = (part, surface.appearance[part].size)
                resizeFace(by: gesture.scale)
            case .changed:
                resizeFace(by: gesture.scale)
            case .ended:
                resizeFace(by: gesture.scale)
                resize = nil
            case .cancelled, .failed:
                resize = nil
            default:
                break
            }
        }

        private func resizeFace(by scale: CGFloat) {
            guard let resize else { return }
            surface.appearance[resize.part].size = resize.size * scale
        }

        private func hit(_ point: CGPoint, in view: UIView) -> OiSeedCucumberPart? {
            OiSeedCucumberViewport(size: view.bounds.size)
                .hitPart(at: point, appearance: surface.appearance, selection: surface.selection)
        }
    }
}
