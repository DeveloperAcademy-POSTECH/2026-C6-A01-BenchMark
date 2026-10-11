//
//  ARView.swift
//  OiDonation
//
//  Created by jiwon hong on 10/11/26.
//

import SwiftUI

struct ARView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                            .padding()
                    }
                }

                Spacer()

                Text("AR 화면")
                    .foregroundStyle(.white)

                Spacer()
            }
        }
    }
}

#Preview {
    ARView()
}
