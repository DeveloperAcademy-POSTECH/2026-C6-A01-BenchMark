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
    @State private var showingPicker = false

    var body: some View {
        OiPostcardColorRingButton { showingPicker = true }
            .frame(width: 44, height: 44)
            .accessibilityLabel("\(title) 색상 선택")
            .accessibilityValue(String(format: "#%06X", color))
            .sheet(isPresented: $showingPicker) {
                OiPostcardNativeColorPicker(title: "\(title) Color", color: $color) { showingPicker = false }
                    .presentationDetents([.height(pickerHeight), .large])
                    .presentationBackgroundInteraction(.enabled(upThrough: .height(pickerHeight)))
                    .presentationDragIndicator(.visible)
            }
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
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        picker.selectedColor = UIColor(Color(oiRGB: color))
        picker.title = title
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
        context.coordinator.parent = self
        if Color(picker.selectedColor).oiRGB != color { picker.selectedColor = UIColor(Color(oiRGB: color)) }
    }
    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: OiPostcardNativeColorPicker
        init(_ parent: OiPostcardNativeColorPicker) { self.parent = parent }
        func colorPickerViewController(_ picker: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
            parent.color = Color(color).oiRGB
        }
        func colorPickerViewControllerDidFinish(_ picker: UIColorPickerViewController) { parent.onFinish() }
    }
}
