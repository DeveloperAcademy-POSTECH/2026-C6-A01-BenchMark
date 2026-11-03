import SwiftUI
import MapKit

struct CampusStoryDetailView: View {
    let story: CampusStory
    let store: CampusStoryStore
    @State private var donationInfo = false
    @State private var selectedImage: CampusImageSelection?
    @State private var showingAllRelated = false

    var body: some View {
        GeometryReader { geometry in
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(story.image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: 275).clipped()
                    .background(CampusStyle.background(story.palette))
                VStack(alignment: .leading, spacing: 30) {
                    heading
                    storyBlock
                    characterAndCard
                    if !story.remoteMediaPaths.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("갤러리")
                            ForEach(story.remoteMediaPaths, id: \.self) { path in
                                OiStoryMediaImage(path: path) { path in
                                    guard let resolver = store.mediaURL else { throw OiServiceError.unavailable }
                                    return try await resolver(path)
                                }.frame(minHeight: 120, maxHeight: 360)
                            }
                        }
                    }
                    location
                    related
                    donor
                    Text("작성·공개는 운영자 검토 기준이며 학교 공식 납입 확인과 다릅니다. 로그인 후 수집 기록이 계정에 저장됩니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(width: max(0, geometry.size.width - 40), alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 25)
            }.frame(width: geometry.size.width)
          }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color(.systemBackground))
        .toolbar(.visible, for: .navigationBar).toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline).toolbarRole(.editor)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 8) {
                Button { donationInfo = true } label: {
                    Text("이어서 기부하기").font(CampusStyle.body(12)).frame(width: 113, height: 46)
                        .foregroundStyle(.black).background(CampusStyle.action.opacity(0.4), in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain)
                CampusCollectButton(story: story, store: store)
            }.padding(.horizontal, 15).padding(.top, 10).padding(.bottom, 6)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25)
                        .fill(.regularMaterial).ignoresSafeArea(edges: .bottom)
                }
        }
        .sheet(isPresented: $donationInfo) { HomeInformationSheet(destination: .donation) }
        .sheet(item: $selectedImage) { image in
            NavigationStack {
                Image(image.name).resizable().scaledToFit().padding(12)
                    .navigationTitle(image.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("닫기") { selectedImage = nil } } }
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(story.title).font(CampusStyle.heading(36)).lineLimit(1).minimumScaleFactor(0.7)
                CampusDonorBadge(size: 23)
                Spacer(minLength: 1)
                CampusTags(story: story)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("기부자 | \(story.donor)")
                Text("위치 | \(story.location)")
                Text("날짜 | \(story.date)")
            }.font(CampusStyle.hand(15))
        }
    }

    private var storyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("기부자 스토리")
            VStack(alignment: .leading, spacing: 14) {
                Text(story.excerpt).font(CampusStyle.hand(18)).lineSpacing(3)
                VStack(spacing: 2) { Divider(); Divider() }
                Text(story.body).font(CampusStyle.body(14)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                .background(Color(red: 0.988, green: 0.945, blue: 0.945), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var characterAndCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("오이 & 카드")
            HStack(spacing: 20) {
                Image(story.image).resizable().scaledToFill().frame(width: 147, height: 220).clipped()
                MYCardArtwork(card: MYCard(id: story.id, title: story.title, image: story.image,
                    school: .postech, order: story.order, body: story.body, donor: story.donor, date: story.date))
                    .frame(maxWidth: .infinity).frame(height: 220)
            }.frame(maxWidth: .infinity)
        }
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("위치")
            if let latitude = story.latitude, let longitude = story.longitude {
                Map(initialPosition: .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)))) {
                    Marker(story.title, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                }.frame(height: 245).clipShape(RoundedRectangle(cornerRadius: 20)).allowsHitTesting(false)
                    .accessibilityLabel("저장한 위치: \(story.location)")
            } else {
                Text("등록된 위치가 없어요.").foregroundStyle(.secondary)
            }
        }
    }
    private var related: some View {
        let items = Array(store.stories(in: story.regionID, sortedBy: .latest).filter { $0.id != story.id }.prefix(3))
        return VStack(spacing: 8) {
            HStack { sectionTitle("이어진 기부"); Spacer(); Text("\(min(items.count, 3))개").font(.headline).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 5).background(CampusStyle.coral, in: Capsule()) }
            ForEach(Array(items.prefix(showingAllRelated ? items.count : 2))) { next in
                NavigationLink(value: CampusDestination.summary(next.id)) { CampusStoryRow(story: next) }.buttonStyle(.plain)
            }
            Button(showingAllRelated ? "접기" : "더보기") { withAnimation { showingAllRelated.toggle() } }
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 36)
                .background(Color(.systemGray6), in: Capsule())
        }
    }
    private var donor: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("기부자 소개")
            HStack(spacing: 15) {
                Image("OiFarmer").resizable().scaledToFit().frame(width: 120, height: 160)
                VStack(alignment: .leading, spacing: 15) {
                    donorField("닉네임", story.donor)
                    donorField("이야기 장소", story.location)
                }
                Spacer(minLength: 0)
            }.padding(14).frame(maxWidth: .infinity).frame(minHeight: 199)
                .background {
                    GeometryReader { g in
                        Image("OiFarmerBackdrop").resizable().scaledToFill()
                            .frame(width: g.size.width, height: g.size.height * 2.374)
                            .offset(y: -g.size.height * 1.374)
                    }.clipped()
                }.clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
    private func donorField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(label).font(.system(size: 14, weight: .heavy)); Text(value).font(.system(size: 15)) }
    }
    private func sectionTitle(_ text: String) -> some View { Text(text).font(.system(size: 24, weight: .bold)).foregroundStyle(CampusStyle.coral) }
}

private struct CampusImageSelection: Identifiable {
    var id: String { name }
    let name: String
    let title: String
}
