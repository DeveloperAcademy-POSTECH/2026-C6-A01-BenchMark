import SwiftUI

struct OiTabBar: View {
    @Binding var selectedTab: AppTab
    let onCamera: () -> Void
    var body: some View {
        GlassEffectContainer(spacing: 12) {
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
                        .background { if selectedTab == tab { Capsule().fill(Color("OiGreen").opacity(0.12)) } }
                    }
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(4)
            .glassEffect(.regular.interactive(), in: Capsule())
            Button(action: onCamera) {
                Image(systemName: "camera.fill").font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.primary).frame(width: 62, height: 62)
                    .glassEffect(.regular.interactive(), in: Circle())
            }.accessibilityLabel("AR 카메라 열기")
        }
        .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
    }
}
