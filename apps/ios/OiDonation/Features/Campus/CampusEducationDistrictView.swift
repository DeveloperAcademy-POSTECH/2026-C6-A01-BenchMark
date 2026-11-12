//
//  CampusEducationDistrictView.swift
//  OiDonation
//
//  Created by Codex on 2026/11/12.
//

import SwiftUI
import WebKit

struct CampusEducationDistrictView: View {
    let onExperienceVisibility: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingExperience = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("함께 짓는 캠퍼스의 내일").font(.title2.bold())
                    if let url = Bundle.main.url(forResource: "education-district-official", withExtension: "jpg"),
                       let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("POSTECH 공식 교육지구 2.0 예상 조감도")
                    }
                    Text("교육지구 2.0 · 건립 예정").font(.headline)
                    Text("박태준학술정보관 옆, 포스빌6과 주차장 부지에 계획된 새로운 배움의 공간을 작은 빛으로 만나보세요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Label("공식 조감도 참고 · 지도 배치는 추정", systemImage: "map")
                        .font(.caption).foregroundStyle(.secondary)
                    if let url = Bundle.main.url(forResource: "education-district-plan", withExtension: "png"),
                       let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("도서관과 생활관 사이 교육지구 공식 배치도")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("작은 빛에 담는 축하·감사·응원").font(.headline)
                        Text("구슬이 모여 건물이 되는 모습을 보고, 메시지와 사진을 담아보세요.")
                        Text("모금 현황 연결 준비 중").font(.subheadline.bold())
                        Text("체험 화면의 금액·참여자·인증은 시연용이며 실제 기부 내역과 연결되지 않습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                    Button { showingExperience = true } label: {
                        Label("빛으로 지은 이야기 체험", systemImage: "sparkles")
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }.buttonStyle(.borderedProminent).tint(CampusStyle.green)
                        .accessibilityIdentifier("education.experience")
                    Link("POSTECH 공식 사업 소개 ↗", destination: CampusEducationDistrict.officialURL)
                        .font(.subheadline).tint(CampusStyle.green)
                }.padding(22)
            }
            .navigationTitle("교육지구 2.0")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
        }
        .presentationDetents([.height(280), .large])
        // The compact guide accompanies the map; dimming it also dims the pearls.
        .presentationBackgroundInteraction(.enabled(upThrough: .height(280)))
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showingExperience, onDismiss: { onExperienceVisibility(false) }) {
            NavigationStack {
                EducationLightExperience()
                    .navigationTitle("빛으로 짓는 내일 · 시연")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { showingExperience = false }.foregroundStyle(.white) } }
            }.preferredColorScheme(.dark)
                .onAppear { onExperienceVisibility(true) }
        }
    }
}
