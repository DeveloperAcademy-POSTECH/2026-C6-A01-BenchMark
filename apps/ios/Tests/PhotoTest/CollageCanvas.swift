// Created by 이돈혁

import SwiftUI
import CoreGraphics

struct CollageCanvas: View {
    @Binding var photos: [CollagePhoto]
    let arrangement: CollageArrangement
    let manual: Bool
    let selectedSlot: Int
    let onSelect: (Int, Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, proxy.size.height * arrangement.aspectRatio)
            let size = CGSize(width: width, height: width / arrangement.aspectRatio)
            ZStack(alignment: .topLeading) {
                Color.white
                ForEach(arrangement.frames.indices, id: \.self) { index in
                    let rect = arrangement.frames[index]
                    let cellSize = CGSize(width: rect.width * size.width, height: rect.height * size.height)
                    CollageCell(photo: $photos[index], size: cellSize, index: index,
                                manual: manual, selected: manual && selectedSlot == index) {
                        onSelect(index, false)
                    }
                    .frame(width: cellSize.width, height: cellSize.height)
                    .offset(x: rect.minX * size.width, y: rect.minY * size.height)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CollageCell: View {
    @Binding var photo: CollagePhoto
    let size: CGSize
    let index: Int
    let manual: Bool
    let selected: Bool
    let onSelect: () -> Void
    @GestureState private var translation = CGSize.zero
    @GestureState private var magnification: CGFloat = 1

    private var liveCrop: CollageCrop {
        CollageCrop(zoom: photo.crop.zoom * magnification,
                    x: photo.crop.x + translation.width / max(1, size.width),
                    y: photo.crop.y + translation.height / max(1, size.height))
    }

    var body: some View {
        ZStack {
            if let image = photo.image {
                let frame = manual ? liveCrop.imageFrame(imageSize: image.size, cellSize: size) : CGRect(origin: .zero, size: size)
                Image(uiImage: image).resizable()
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            } else {
                Color("OiLight")
                VStack(spacing: 6) {
                    Image(systemName: "plus").font(.title2)
                    Text("\(index + 1)").font(.caption)
                }.foregroundStyle(Color("OiGreen"))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay {
            if manual {
                Rectangle().strokeBorder(selected ? Color("OiGreen") : Color.white.opacity(0.8), lineWidth: selected ? 3 : 1)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if manual { onSelect() } }
        .gesture(DragGesture(minimumDistance: 4)
            .updating($translation) { value, state, _ in
                if selected && photo.image != nil { state = value.translation }
            }
            .onEnded { value in
                guard selected, let image = photo.image else { return }
                var crop = photo.crop
                crop.x += value.translation.width / max(1, size.width)
                crop.y += value.translation.height / max(1, size.height)
                photo.crop = crop.clamped(imageSize: image.size, cellSize: size)
            }, including: selected ? .all : .none)
        .simultaneousGesture(MagnifyGesture()
            .updating($magnification) { value, state, _ in
                if selected && photo.image != nil { state = value.magnification }
            }
            .onEnded { value in
                guard selected, let image = photo.image else { return }
                var crop = photo.crop
                crop.zoom *= value.magnification
                photo.crop = crop.clamped(imageSize: image.size, cellSize: size)
            }, including: selected ? .all : .none)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(index + 1)번 칸, \(photo.image == nil ? "사진 없음" : "사진 있음")")
        .accessibilityValue(selected ? "선택됨" : "")
        .accessibilityAddTraits(manual ? .isButton : .isImage)
        .accessibilityAction { if manual { onSelect() } }
    }
}
