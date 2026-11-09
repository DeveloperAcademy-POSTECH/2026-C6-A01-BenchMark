//
//  OiSeedCucumberCustomizationView.swift
//  OiDonation
//
//  Created by 이돈혁 on 11/9/26.
//

import SwiftUI

struct OiSeedCucumberCustomizationView: View {
    var body: some View {
        Image("MYEmptyCucumber")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 280)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
            .accessibilityLabel("맨몸 오이")
            .navigationTitle("오이 커스텀")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        OiSeedCucumberCustomizationView()
    }
}
