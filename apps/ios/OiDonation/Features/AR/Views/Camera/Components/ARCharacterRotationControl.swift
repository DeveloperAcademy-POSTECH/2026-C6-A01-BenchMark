//
//  ARCharacterRotationControl.swift
//  OiDonation
//
//  Created by Codex on 2026/11/17.
//

import SwiftUI

struct ARCharacterRotationControl: View {
    let angle: Float
    let rotate: (Float) -> Void
    @State private var startAngle: Float?
    @GestureState private var dragging = false

    var body: some View {
        ZStack(alignment: .top) {
            Image("ARCharacterRotationArrow")
                .frame(width: 58, height: 15.1437)
                .offset(y: 7)
            Text("360°")
                .font(.custom("Paperlogy-4Regular", size: 16))
                .tracking(0.32)
                .foregroundStyle(Color(red: 106/255, green: 106/255, blue: 106/255))
                .offset(x: 2)
        }
        .frame(width: 58, height: 23)
        .frame(width: 104, height: 48)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3)
            .updating($dragging) { _, active, _ in active = true }
            .onChanged { value in
                if startAngle == nil { startAngle = angle }
                rotate((startAngle ?? angle) + Float(value.translation.width) * 0.6)
            }
            .onEnded { _ in startAngle = nil })
        .onChange(of: dragging) { _, active in if !active { startAngle = nil } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("캐릭터 회전")
        .accessibilityValue("\(Int(angle))도")
        .accessibilityHint("좌우로 드래그해 회전합니다")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: rotate(angle + 15)
            case .decrement: rotate(angle - 15)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("ar.camera.characterRotation")
    }
}

#Preview {
    ARCharacterRotationControl(angle: 0, rotate: { _ in })
        .frame(width: 200, height: 100).background(.white)
}
