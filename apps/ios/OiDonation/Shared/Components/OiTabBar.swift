import SwiftUI

struct OiTabBar: View {
    @Binding var selectedTab: AppTab
    let onCamera: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    Button { selectedTab = tab } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.symbol).font(.system(size: 23, weight: .semibold))
                            Text(tab.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        }
                        .foregroundStyle(selectedTab == tab ? Color("OiGreen") : Color.primary)
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background { if selectedTab == tab { Capsule().fill(Color("OiSoft")) } }
                    }
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(4).background(.regularMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
            Button(action: onCamera) {
                Image(systemName: "camera.fill").font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.primary).frame(width: 62, height: 62)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
            }.accessibilityLabel("AR 카메라 열기")
        }
        .buttonStyle(.plain).shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
        .background(Color.white)
    }
}
