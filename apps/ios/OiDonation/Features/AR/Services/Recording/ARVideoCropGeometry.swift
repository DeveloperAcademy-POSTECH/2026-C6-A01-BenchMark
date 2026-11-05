import CoreGraphics

/// 윈도 왼쪽 위를 기준으로 한 상대 좌표를 정방향 영상의 짝수 크기 출력 좌표로 변환합니다.
struct ARVideoCropGeometry {
    let size: CGSize
    let transform: CGAffineTransform

    init?(naturalSize: CGSize, preferredTransform: CGAffineTransform, normalizedRect: CGRect) {
        guard naturalSize.width > 0, naturalSize.height > 0,
              [normalizedRect.minX, normalizedRect.minY, normalizedRect.width, normalizedRect.height].allSatisfy({ $0.isFinite }) else { return nil }
        let crop = normalizedRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !crop.isNull, !crop.isEmpty else { return nil }
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized
        size = CGSize(width: floor(crop.width * oriented.width / 2) * 2,
                      height: floor(crop.height * oriented.height / 2) * 2)
        guard size.width >= 2, size.height >= 2 else { return nil }
        transform = preferredTransform.concatenating(CGAffineTransform(
            translationX: -oriented.minX - crop.minX * oriented.width,
            y: -oriented.minY - crop.minY * oriented.height))
    }
}
