import SwiftUI

enum HomeDestination: String, Identifiable {
    case introduction, donation, receipt, benefits, news, recurring, notifications, profile, myDonations, map
    var id: String { rawValue }
    var title: String {
        switch self {
        case .introduction: "오이기부 소개"
        case .donation: "기부 시작"
        case .receipt: "기부금영수증"
        case .benefits: "이벤트/혜택"
        case .news: "오이 소식"
        case .recurring: "정기후원"
        case .notifications: "알림"
        case .profile: "내 프로필"
        case .myDonations: "내 기부"
        case .map: "벤치지도"
        }
    }
    var message: String {
        switch self {
        case .introduction: "오래 남는 이야기 기부. 소액 기부로 캠퍼스의 장소에 오이와 이야기를 남기고, 다른 이용자가 3D 지도와 현장 AR에서 발견하는 경험입니다."
        case .donation, .recurring:
            "기부는 안내된 정식 수납처의 기존 절차를 이용해 주세요. 운영자는 이체 내역 등 제출 자료를 검토해 앱의 작성 승인을 판단해요.\n\n\(OiWritingGuidance.overview) \(OiWritingGuidance.publication)\n\n공식 납입 확인과 세액공제용 영수증 발급은 수납처에 문의해 주세요."
        case .receipt: "기부금영수증은 POSTECH에서 발급합니다. 공식 발전기금 사이트에서 확인하거나 학교에 문의해 주세요."
        case .benefits: "새로운 이벤트와 기부자 혜택이 준비되면 안내드릴게요."
        case .news: "새로운 오이기부 소식이 준비되면 이곳에서 전해드릴게요."
        case .notifications: "아직 새로운 알림이 없어요."
        case .profile: "로그인 후 나의 정보와 이야기를 관리할 수 있어요."
        case .myDonations: "아직 확인된 기부 내역이 없어요. 학교에서 납입을 확인한 이후 진행 상황을 안내드립니다."
        case .map: "참여 가능한 벤치는 학교 확인 후 안내드릴게요."
        }
    }
}

struct HomeInformationSheet: View {
    let destination: HomeDestination
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(destination.message).font(.body)
                    if [.donation, .recurring, .receipt].contains(destination) {
                        Link("POSTECH 공식 기부 사이트", destination: OfficialDonationWebsite.url)
                            .buttonStyle(.borderedProminent).tint(Color("OiGreen"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .navigationTitle(destination.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

