import SwiftUI
import MapKit

struct CampusStoryDetailView: View {
    let story: CampusStory
    let store: CampusStoryStore
    @State private var selectedImage: CampusImageSelection?
    @State private var showingCard = false
    @State private var showingAllRelated = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if let hero = story.example?.heroImage { Image(hero).resizable().scaledToFill() }
                    else { CampusCucumberPortrait(story: story) }
                }
                    .frame(width: geometry.size.width, height: 275).clipped()
                    .background(CampusStyle.background(story.palette))
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 50) {
                    if let author = story.authorID, let id = UUID(uuidString: story.id) {
                        OiStorySafetyButton(storyID: id, authorID: author, authorName: story.donor, onBlock: { dismiss() })
                    }
                    heading
                    donor
                    storyBlock
                    characterAndCard
                    if let images = story.example?.galleryImages, !images.isEmpty { exampleGallery(images) }
                    if !story.remoteMediaPaths.isEmpty { remoteGallery }
                    location
                    related
                    Text(story.isExample ? "디자인을 확인하기 위한 예시입니다. 실제 기부·수집 기록에 포함되지 않아요." : "공개된 이야기는 운영자가 검토한 콘텐츠입니다. 로그인 후 수집 기록이 계정에 저장됩니다.")
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
                Button { store.createStoryAction?() } label: {
                    Text("이어서 기부하기").font(CampusStyle.medium(16)).frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(.black).background(CampusStyle.secondaryAction, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).disabled(story.isExample || store.createStoryAction == nil)
                    .accessibilityIdentifier("campus.story.continue")
                CampusCollectButton(story: story, store: store)
            }.padding(.horizontal, 15).padding(.top, 10).padding(.bottom, 6)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 25, topTrailingRadius: 25)
                        .fill(.regularMaterial).ignoresSafeArea(edges: .bottom)
                }
        }
        .fullScreenCover(item: $selectedImage) { image in
            CampusArtworkOverlay(title: image.title) {
                if let name = image.name { Image(name).resizable().scaledToFit() }
                else if let path = image.remotePath {
                    OiStoryMediaImage(path: path, loadURL: mediaURL).aspectRatio(contentMode: .fit)
                }
            }
        }
        .fullScreenCover(isPresented: $showingCard) {
            CampusArtworkOverlay(title: story.title + " 카드") { CampusStoryCardArtwork(story: story) }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 12) {
            if story.isExample { CampusExampleBadge() }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    storyTitle.fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 1)
                    CampusTags(story: story, size: 18).fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 6) {
                    storyTitle
                    CampusTags(story: story, size: 18)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("위치 | \(story.location)")
                Text("날짜 | \(story.date)")
            }.font(.custom("Paperlogy-3Light", size: 15, relativeTo: .body)).tracking(0.3)
        }
    }

    private var storyTitle: some View {
        Text(story.title).font(CampusStyle.characterTitle(35)).tracking(1.4)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private var storyBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("기부자 스토리")
            VStack(alignment: .leading, spacing: 24) {
                if let introduction = story.example?.introduction, !introduction.isEmpty {
                    Text(introduction).font(CampusStyle.body(16)).lineSpacing(3)
                }
                if story.body.isEmpty {
                    Text("아직 작성된 이야기가 없어요.").font(CampusStyle.body(14)).foregroundStyle(.secondary)
                } else {
                    Text(story.body).font(.custom("Paperlogy-3Light", size: 14, relativeTo: .body))
                        .tracking(0.28).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(Color(white: 236 / 255), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var characterAndCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("오이 & 카드")
            HStack(spacing: 20) {
                CampusCucumberPortrait(story: story).frame(maxWidth: .infinity).frame(height: 220)
                Button { showingCard = true } label: {
                    CampusStoryCardArtwork(story: story).frame(maxWidth: .infinity).frame(height: 220)
                }.buttonStyle(.plain)
                    .accessibilityLabel("오이 카드 확대 보기")
            }.frame(maxWidth: .infinity)
        }
    }

    private func mediaURL(_ path: String) async throws -> URL {
        guard let resolver = store.mediaURL else { throw OiServiceError.unavailable }
        return try await resolver(path)
    }

    private var remoteGallery: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionTitle("갤러리")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(story.remoteMediaPaths.enumerated()), id: \.element) { index, path in
                    Button {
                        selectedImage = .init(name: nil, title: "\(story.title) 사진 \(index + 1)", remotePath: path)
                    } label: {
                        OiStoryMediaImage(path: path, allowsRetry: false, loadURL: mediaURL)
                            .frame(height: index.isMultiple(of: 3) ? 121 : 109)
                            .clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityLabel("갤러리 사진 \(index + 1) 확대 보기")
                }
            }
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
            } else if story.isExample {
                GeometryReader { geometry in
                    Image("OiStoryLocation").resizable()
                        .frame(width: geometry.size.width * 387 / 362, height: geometry.size.width * 662 / 362)
                        .offset(x: -geometry.size.width * 25 / 362, y: -geometry.size.width * 314.5 / 362)
                    Image(systemName: "mappin.circle.fill").font(.system(size: 30)).foregroundStyle(.red)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }.frame(height: 245).clipped().clipShape(RoundedRectangle(cornerRadius: 20))
                    .allowsHitTesting(false)
                    .accessibilityLabel("예시 장소: \(story.location)")
                Text(story.location).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("등록된 위치가 없어요.").foregroundStyle(.secondary)
            }
        }
    }
    private var related: some View {
        let items = story.example.map { example in example.relatedIDs.compactMap { store.story($0) } }
            ?? Array(store.stories(in: story.regionID, sortedBy: .latest).filter { $0.id != story.id }.prefix(3))
        return VStack(spacing: 8) {
          if !items.isEmpty {
            HStack { sectionTitle(story.isExample ? "이어진 기부 · 예시" : "같은 장소의 이야기"); Spacer(); Text("\(items.count)개").font(.headline).foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 5).background(CampusStyle.sectionGreen, in: Capsule()) }
            ForEach(Array(items.prefix(showingAllRelated ? items.count : 2))) { next in
                NavigationLink(value: CampusDestination.summary(next.id)) { CampusStoryRow(story: next) }.buttonStyle(.plain)
            }
            if items.count > 2 { Button(showingAllRelated ? "접기" : "더보기") { withAnimation { showingAllRelated.toggle() } }
                .font(.system(size: 14, weight: .bold)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 36)
                .background(Color(.systemGray6), in: Capsule()) }
          }
        }
    }

    private func exampleGallery(_ images: [String]) -> some View {
        // The Figma collage has 2 / 2 / 2 / 3 / 2 photographs per row.
        let rows = [[0, 1], [2, 3], [4, 5], [6, 7, 8], [9, 10]]
        let weights: [[CGFloat]] = [[163, 195], [213, 145], [1, 1], [68, 215, 68], [1, 1]]
        let heights: [CGFloat] = [109, 120, 101, 121, 101]
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("갤러리")
            ForEach(rows.indices, id: \.self) { row in
                GeometryReader { geometry in
                    let available = max(0, geometry.size.width - CGFloat(rows[row].count - 1) * 8)
                    HStack(spacing: 8) {
                        ForEach(Array(rows[row].enumerated()), id: \.element) { column, index in
                            if images.indices.contains(index) {
                                Button { selectedImage = .init(name: images[index], title: "6냥이의 추억 \(index + 1)") } label: {
                                    Image(images[index]).resizable().scaledToFill()
                                        .frame(width: available * weights[row][column] / weights[row].reduce(0, +), height: heights[row])
                                        .clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                        .contentShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityLabel("갤러리 사진 \(index + 1) 확대 보기")
                            }
                        }
                    }
                }.frame(height: heights[row])
            }
        }
    }
    private var donor: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("기부자 소개")
            HStack(spacing: 14) {
                Image("OiFarmer").resizable().scaledToFill().frame(width: 50, height: 50)
                    .background(CampusStyle.secondaryAction, in: Circle()).clipShape(Circle())
                    .overlay(Circle().stroke(CampusStyle.green, lineWidth: 1.5)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(story.isExample ? "디자인 예시 작성자" : "이야기를 남긴 농부")
                        .font(CampusStyle.body(12)).foregroundStyle(.secondary)
                    Text(story.donor).font(CampusStyle.semibold(22)).tracking(0.44)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity)
                .background(Color(red: 241 / 255, green: 244 / 255, blue: 236 / 255),
                            in: RoundedRectangle(cornerRadius: 20))
        }
    }
    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.custom("Paperlogy-7Bold", size: 26, relativeTo: .title2)).foregroundStyle(CampusStyle.sectionGreen)
    }
}

private struct CampusImageSelection: Identifiable {
    var id: String { name ?? remotePath ?? title }
    let name: String?
    let title: String
    var remotePath: String? = nil
}
