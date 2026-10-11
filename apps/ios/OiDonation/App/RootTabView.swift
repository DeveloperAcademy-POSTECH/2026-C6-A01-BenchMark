//
//  RootTabView.swift
//  OiDonation
//
//  Created by jiwon hong on 10/11/26.
//

import SwiftUI

struct RootTabView: View {
    @State private var isARPresented = false

    var body: some View {
        HomeView {
            isARPresented = true
        }
        .fullScreenCover(isPresented: $isARPresented) {
            ARView()
        }
    }
}

#Preview {
    RootTabView()
}
