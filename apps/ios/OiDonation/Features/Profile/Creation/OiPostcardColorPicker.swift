//
//  OiPostcardColorPicker.swift
//  OiDonation
//
//  Created by Codex on 2026/11/13.
//

import SwiftUI
import UIKit

/// Keep the Figma ring visible and make opening the real picker an explicit action.
struct OiPostcardColorRing: View {
    let title: String
    @Binding var color: UInt32
    var pickerHeight: CGFloat = 500
    var onReset: (() -> Void)? = nil
    var opacity: Binding<Double>? = nil
    @State private var showingPicker = false

    var body: some View {
        OiPostcardColorRingButton { showingPicker = true }
            .frame(width: 44, height: 44)
            .accessibilityLabel("\(title) 색상 선택")
            .accessibilityValue(String(format: "#%06X", color))
            .sheet(isPresented: $showingPicker) {
                OiPostcardColorSheet(color: $color, opacity: opacity, onReset: onReset)
                    .presentationDetents([.height(pickerHeight), .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(pickerHeight)))
                    .presentationDragIndicator(.visible)
            }
    }

}

/// Reset sheets retain their upper toolbar; other sheets use the native Color row.
private struct OiPostcardColorSheet: View {
    @Binding var color: UInt32
    var opacity: Binding<Double>?
    var onReset: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        OiPostcardNativeColorPicker(title: "Color", color: $color, opacity: opacity,
            onReset: onReset) { dismiss() }
    }
}

struct OiPostcardOpacityControl: View {
    @Binding var opacity: Double
    var body: some View {
        HStack(spacing: 12) {
            Text("불투명도").font(.caption)
            Slider(value: $opacity, in: 0...1, step: 0.01)
                .accessibilityLabel("불투명도")
                .accessibilityIdentifier("oi.postcard.opacity.slider")
            Text("\(Int((OiCardOpacity.normalized(opacity) * 100).rounded()))%")
                .font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
        }.frame(minHeight: 36)
    }
}

/// A real 44pt control remains hittable inside the scaled Figma color diagram.
private struct OiPostcardColorRingButton: UIViewRepresentable {
    let open: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(open: open) }
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(named: "OiPostcardDiagram-imgEllipse19")?.withRenderingMode(.alwaysOriginal)
        configuration.contentInsets = .init(top: 2, leading: 2, bottom: 2, trailing: 2)
        button.configuration = configuration
        button.imageView?.contentMode = .scaleAspectFit
        button.accessibilityIdentifier = "oi.postcard.color-ring.control"
        button.addAction(UIAction { [weak coordinator = context.coordinator] _ in coordinator?.open() },
            for: .primaryActionTriggered)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) { context.coordinator.open = open }
    final class Coordinator {
        var open: () -> Void
        init(open: @escaping () -> Void) { self.open = open }
    }
}

struct OiPostcardNativeColorPicker: UIViewControllerRepresentable {
    let title: String
    @Binding var color: UInt32
    var opacity: Binding<Double>? = nil
    var onReset: (() -> Void)? = nil
    let onFinish: () -> Void

    private var selectedColor: UIColor {
        UIColor(Color(oiRGB: color)).withAlphaComponent(OiCardOpacity.normalized(opacity?.wrappedValue))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = opacity != nil
        picker.selectedColor = selectedColor
        picker.title = title
        picker.delegate = context.coordinator
        if onReset != nil {
            // System bar items supply the confirmation appearance without nested glass.
            let apply = UIBarButtonItem(barButtonSystemItem: .done,
                target: context.coordinator, action: #selector(Coordinator.finish))
            apply.style = .prominent
            apply.accessibilityLabel = "색상 적용"
            apply.accessibilityIdentifier = "oi.postcard.color.apply"
            picker.navigationItem.rightBarButtonItem = apply
            let reset = UIBarButtonItem(title: "초기화", style: .plain,
                target: context.coordinator, action: #selector(Coordinator.reset))
            reset.accessibilityIdentifier = "oi.postcard.color.reset"
            picker.navigationItem.leftBarButtonItem = reset
            picker.navigationItem.title = ""
            picker.navigationItem.largeTitleDisplayMode = .never
            let navigation = UINavigationController(rootViewController: picker)
            navigation.navigationBar.tintColor = .systemBlue
            return navigation
        }
        let container = UIViewController()
        container.addChild(picker)
        container.view.addSubview(picker.view)
        picker.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            picker.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            picker.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            picker.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            picker.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor)
        ])
        picker.didMove(toParent: container)
        let apply = UIButton(type: .system)
        var configuration = UIButton.Configuration.prominentGlass()
        configuration.image = UIImage(systemName: "checkmark")
        configuration.cornerStyle = .capsule
        apply.configuration = configuration
        apply.tintColor = .systemBlue
        apply.accessibilityLabel = "색상 적용"
        apply.accessibilityIdentifier = "oi.postcard.color.apply"
        apply.addAction(UIAction { [weak coordinator = context.coordinator] _ in
            coordinator?.parent.onFinish()
        }, for: .primaryActionTriggered)
        container.view.addSubview(apply)
        apply.translatesAutoresizingMaskIntoConstraints = false
        // iOS 26 has a leading eyedropper and a 56pt title row; iOS 27 moves it
        // to the trailing edge and uses 72pt. Mirror it without touching native views.
        let horizontal: NSLayoutConstraint
        let titleRowHeight: CGFloat
        if #available(iOS 27, *) {
            horizontal = apply.leadingAnchor.constraint(equalTo: container.view.safeAreaLayoutGuide.leadingAnchor, constant: 10)
            titleRowHeight = 72
        } else {
            horizontal = apply.trailingAnchor.constraint(equalTo: container.view.safeAreaLayoutGuide.trailingAnchor, constant: -10)
            titleRowHeight = 56
        }
        NSLayoutConstraint.activate([
            apply.topAnchor.constraint(equalTo: container.view.safeAreaLayoutGuide.topAnchor, constant: (titleRowHeight - 44) / 2),
            horizontal,
            apply.widthAnchor.constraint(equalToConstant: 44),
            apply.heightAnchor.constraint(equalToConstant: 44)
        ])
        return container
    }
    func updateUIViewController(_ container: UIViewController, context: Context) {
        context.coordinator.parent = self
        let picker = (container as? UINavigationController)?.viewControllers.first as? UIColorPickerViewController
            ?? container.children.first as? UIColorPickerViewController
        guard let picker else { return }
        if Color(picker.selectedColor).oiRGB != color ||
            abs(Double(picker.selectedColor.cgColor.alpha) - Double(selectedColor.cgColor.alpha)) > 0.0001 {
            picker.selectedColor = selectedColor
        }
    }
    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: OiPostcardNativeColorPicker
        init(_ parent: OiPostcardNativeColorPicker) { self.parent = parent }
        @objc func finish() { parent.onFinish() }
        @objc func reset() { parent.onReset?() }
        func colorPickerViewController(_ picker: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
            let rgb = Color(color).oiRGB
            if parent.color != rgb { parent.color = rgb }
            parent.opacity?.wrappedValue = OiCardOpacity.normalized(Double(color.cgColor.alpha))
        }
        func colorPickerViewControllerDidFinish(_ picker: UIColorPickerViewController) { parent.onFinish() }
    }
}
