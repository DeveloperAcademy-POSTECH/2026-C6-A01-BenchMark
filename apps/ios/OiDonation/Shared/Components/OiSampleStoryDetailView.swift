//
//  OiSampleStoryDetailView.swift
//  OiDonation / OiDonationClip
//
//  Created by Codex on 11/7/26.
//

import SwiftUI

/// Sample-only story presentation: no account, remote media resolver or donation actions.
struct OiSampleStoryDetailView: View {
    let story: CampusStory
    let onCollect: () -> Void
    @State private var selectedImage: SampleImage?
    @State private var showingCard = false
    @State private var showingDonationNotice = false
    private var isCats: Bool { story.id == OiSampleStory.id }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image(isCats ? "OiSampleGallery02" : story.portraitImage).resizable()
                        .aspectRatio(contentMode: isCats ? .fill : .fit)
                        .frame(width: geometry.size.width, height: 275).clipped()
                        .background(CampusStyle.secondaryAction).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 42) {
                        heading
                        donor
                        storyBlock
                        characterAndCard
                        if isCats { gallery }
                        location
                        related
                        Text(OiSampleStory.notice).font(.caption).foregroundStyle(.secondary)
                    }.padding(20).frame(width: geometry.size.width)
                }
            }
        }
        .background(.white).foregroundStyle(.black).ignoresSafeArea(edges: .top)
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                Button { showingDonationNotice = true } label: {
                    Text("이어서 기부하기").font(CampusStyle.medium(16)).frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.black)
                        .background(CampusStyle.secondaryAction, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityIdentifier("sample.donationInfo")
                OiSampleCollectButton(story: story, onCollect: onCollect)
            }.padding(.horizontal, 20).padding(.vertical, 12)
                .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25))
        }
        .alert("체험용 이야기예요", isPresented: $showingDonationNotice) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("예시 이야기에 실제 기부를 연결하지 않아요. 실제 참여는 체험을 닫고 앱의 기부 안내에서 시작할 수 있어요.")
        }
        .sheet(item: $selectedImage) { item in
            OiSampleArtworkSheet(title: item.title) { Image(item.name).resizable().scaledToFit() }
        }
        .sheet(isPresented: $showingCard) {
            OiSampleArtworkSheet(title: story.title + " · 예시 카드") { OiSampleStoryCard(story: story) }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    title.fixedSize(horizontal: true, vertical: false)
                    CampusTags(story: story, size: 18)
                }
                VStack(alignment: .leading, spacing: 6) { title; CampusTags(story: story, size: 18) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("위치 | " + story.location)
                Text("날짜 | " + story.date)
            }.font(.custom("Paperlogy-3Light", size: 15, relativeTo: .body))
        }
    }

    private var title: some View {
        Text(story.title).font(CampusStyle.characterTitle(35)).accessibilityAddTraits(.isHeader)
    }

    private var donor: some View {
        section("기부자 소개") {
            HStack(spacing: 14) {
                Image("OiFarmer").resizable().scaledToFill().frame(width: 50, height: 50)
                    .background(CampusStyle.secondaryAction, in: Circle()).clipShape(Circle())
                    .overlay(Circle().stroke(CampusStyle.green, lineWidth: 1.5)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("체험용 예시 작성자").font(CampusStyle.body(12)).foregroundStyle(.secondary)
                    Text(story.donor).font(CampusStyle.semibold(20))
                }
                Spacer(minLength: 0)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 241 / 255, green: 244 / 255, blue: 236 / 255), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var storyBlock: some View {
        section("기부자 스토리") {
            VStack(alignment: .leading, spacing: 24) {
                if !story.excerpt.isEmpty {
                    Text(story.excerpt).font(CampusStyle.body(16)).lineSpacing(3)
                }
                Text(story.body.isEmpty ? "이 예시에는 작성된 이야기 본문이 없어요. 6냥이오이에서 이야기와 AR 수집을 체험해 보세요." : story.body)
                    .font(.custom("Paperlogy-3Light", size: 14, relativeTo: .body))
                    .lineSpacing(5).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 236 / 255), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var characterAndCard: some View {
        section("오이 & 카드") {
            HStack(spacing: 20) {
                Image(story.portraitImage).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 220)
                    .accessibilityLabel(story.title)
                Button { showingCard = true } label: {
                    OiSampleStoryCard(story: story).frame(maxWidth: .infinity).frame(height: 220)
                }.buttonStyle(.plain).accessibilityLabel("오이 카드 확대 보기")
            }
        }
    }

    private var gallery: some View {
        let rows = [[1, 2], [3, 4], [5, 6], [7, 8, 9], [10, 11]]
        let weights: [[CGFloat]] = [[163, 195], [213, 145], [1, 1], [68, 215, 68], [1, 1]]
        let heights: [CGFloat] = [109, 120, 101, 121, 101]
        return section("갤러리") {
            VStack(spacing: 8) {
                ForEach(rows.indices, id: \.self) { row in
                    GeometryReader { geometry in
                        let available = max(0, geometry.size.width - CGFloat(rows[row].count - 1) * 8)
                        HStack(spacing: 8) {
                            ForEach(Array(rows[row].enumerated()), id: \.element) { column, index in
                                let asset = String(format: "OiSampleGallery%02d", index)
                                Button { selectedImage = SampleImage(name: asset, title: "6냥이의 추억 \(index)") } label: {
                                    Image(asset).resizable().scaledToFill()
                                        .frame(width: available * weights[row][column] / weights[row].reduce(0, +), height: heights[row])
                                        .clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                        .contentShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityLabel("갤러리 사진 \(index) 확대 보기")
                            }
                        }
                    }.frame(height: heights[row])
                }
            }
        }
    }

    private var location: some View {
        section("위치") {
            GeometryReader { geometry in
                Image("OiStoryLocation").resizable()
                    .frame(width: geometry.size.width * 387 / 362, height: geometry.size.width * 662 / 362)
                    .offset(x: -geometry.size.width * 25 / 362, y: -geometry.size.width * 314.5 / 362)
                Image(systemName: "mappin.circle.fill").font(.system(size: 30)).foregroundStyle(.red)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }.frame(height: 245).clipped().clipShape(RoundedRectangle(cornerRadius: 20))
                .accessibilityLabel("예시 장소: " + story.location)
            Text(story.location).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var related: some View {
        section("이어진 기부 · 예시") {
            ForEach(CampusStoryExamples.stories.filter { $0.id != story.id }) { item in
                NavigationLink(value: CampusDestination.summary(item.id)) {
                    CampusStoryRow(story: item, outlined: true)
                }.buttonStyle(.plain)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.custom("Paperlogy-7Bold", size: 26, relativeTo: .title2))
                .foregroundStyle(CampusStyle.sectionGreen).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private struct SampleImage: Identifiable {
        var id: String { name }
        let name: String
        let title: String
    }
}
