import SwiftUI

struct PlaquePlacementEditor: View {
    @Environment(\.dismiss) private var dismiss
    let photo: CGImage?
    @Binding var placement: PlaquePhotoPlacement
    @State private var draft = PlaquePhotoPlacement.centered
    private let names = ["왼쪽 위", "오른쪽 위", "오른쪽 아래", "왼쪽 아래"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("취소") { dismiss() }.frame(minHeight: 44)
                Spacer()
                Text("명패 부착 위치").font(.headline)
                Spacer()
                Button("적용") { placement = draft; dismiss() }
                    .frame(minHeight: 44).disabled(!draft.isValid || photo == nil)
            }.padding(.horizontal, 20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("명패가 붙을 곳의 네 모서리를 움직여 주세요.")
                    Text("종이 모형이나 실측으로 위치와 크기를 맞추면 더 정확해요. 사진만으로 실제 크기는 확인할 수 없습니다.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let photo {
                        GeometryReader { geometry in
                            ZStack {
                                Image(decorative: photo, scale: 1).resizable().scaledToFit()
                                Path { path in
                                    let points = draft.corners.map { CGPoint(x: $0.x * geometry.size.width, y: $0.y * geometry.size.height) }
                                    path.addLines(points); path.closeSubpath()
                                }
                                .fill(draft.isValid ? Color("OiGreen").opacity(0.3) : .red.opacity(0.3))
                                ForEach(0..<4, id: \.self) { index in
                                    let point = draft.corners[index]
                                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
                                        .frame(width: 44, height: 44)
                                        .background(draft.isValid ? Color("OiGreen") : .red, in: Circle())
                                        .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("placementPhoto"))
                                            .onChanged { value in
                                                set(index, x: value.location.x / geometry.size.width,
                                                    y: value.location.y / geometry.size.height)
                                            })
                                        .accessibilityLabel("명패 \(names[index]) 모서리")
                                }
                            }.coordinateSpace(name: "placementPhoto")
                        }.aspectRatio(CGFloat(photo.width) / CGFloat(photo.height), contentMode: .fit)
                    } else { ContentUnavailableView("사진이 없어요", systemImage: "photo") }
                    // Also provides a precise, VoiceOver-accessible alternative to dragging.
                    ForEach(0..<4, id: \.self) { index in
                        VStack(alignment: .leading) {
                            Text("\(index + 1). \(names[index])").font(.subheadline.bold())
                            Slider(value: binding(index, horizontal: true), in: 0...1)
                                .accessibilityLabel("\(names[index]) 가로 위치")
                            Slider(value: binding(index, horizontal: false), in: 0...1)
                                .accessibilityLabel("\(names[index]) 세로 위치")
                        }
                    }
                    if !draft.isValid { Text("모서리가 겹치지 않도록 다시 배치해 주세요.").foregroundStyle(.red) }
                    Button("가운데로 초기화") { draft = .centered }
                }.padding(24)
            }
            .onAppear { draft = placement.isValid ? placement : .centered }
        }
    }

    private func set(_ index: Int, x: Double, y: Double) {
        let point = PlaquePhotoPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))
        switch index {
        case 0: draft.topLeft = point
        case 1: draft.topRight = point
        case 2: draft.bottomRight = point
        default: draft.bottomLeft = point
        }
    }
    private func binding(_ index: Int, horizontal: Bool) -> Binding<Double> {
        Binding(get: { horizontal ? draft.corners[index].x : draft.corners[index].y }, set: { value in
            let p = draft.corners[index]
            set(index, x: horizontal ? value : p.x, y: horizontal ? p.y : value)
        })
    }
}
