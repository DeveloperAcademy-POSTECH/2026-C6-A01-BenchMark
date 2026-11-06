//
//  OiSupportView.swift
//  OiDonation / OiDonationClip
//
//  Created by 이돈혁 on 11/6/26.
//

import SwiftUI
import UIKit

struct OiSupportView: View {
    static let email = "8enchMark666@gmail.com"
    private static let repository = "https://github.com/DeveloperAcademy-POSTECH/2026-C6-A01-BenchMark"
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var openFailed = false

    var body: some View {
        NavigationStack {
            List {
                Section("개인정보") {
                    Button("개인정보처리방침") {
                        open(Self.repository + "/blob/main/README.md#개인정보-처리방침")
                    }
                    Text("계정·이야기·사진과 증빙의 처리, 외부 서비스 이용, 보관·삭제 방법을 확인하세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("벤치마크 운영팀 문의") {
                    Button("이메일로 문의하기") { open("mailto:" + Self.email) }
                    Text(Self.email).textSelection(.enabled)
                    Button("이메일 주소 복사") { UIPasteboard.general.string = Self.email }
                    Text("개인정보 열람·정정·삭제, 콘텐츠 신고와 이용 문의를 받습니다. 비밀번호·인증번호나 증빙 원본을 보내지 마세요. 필요한 정보는 운영팀 안내 후 전달해 주세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("공개 지원") {
                    Button("지원 안내") { open(Self.repository + "/blob/main/README.md#지원") }
                    Button("GitHub에 일반 오류 제보") { open(Self.repository + "/issues") }
                    Text("GitHub 이슈는 공개됩니다. 개인정보와 신고 상세 내용은 이메일로 보내 주세요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("개인정보 및 지원")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } } }
            .alert("연결을 열 수 없어요", isPresented: $openFailed) {
                Button("확인", role: .cancel) {}
            } message: { Text("네트워크와 브라우저·메일 앱 설정을 확인해 주세요. 문의는 이메일 주소를 복사해 이용할 수 있어요.") }
        }
    }

    private func open(_ value: String) {
        guard let url = URL(string: value) else { openFailed = true; return }
        openURL(url) { accepted in openFailed = !accepted }
    }
}
