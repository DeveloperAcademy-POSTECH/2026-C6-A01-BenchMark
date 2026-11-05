import CoreGraphics

@main struct ARVideoCropGeometryChecks {
    static func main() {
        let crop = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)
        let identity = ARVideoCropGeometry(naturalSize: CGSize(width: 1000, height: 2000), preferredTransform: .identity, normalizedRect: crop)!
        assert(identity.size == CGSize(width: 800, height: 1200))
        assert(CGPoint(x: 100, y: 400).applying(identity.transform) == .zero)
        let rotated = ARVideoCropGeometry(naturalSize: CGSize(width: 2000, height: 1000), preferredTransform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1000, ty: 0), normalizedRect: crop)!
        assert(rotated.size == identity.size)
        assert(CGPoint(x: 400, y: 900).applying(rotated.transform) == .zero)
        let odd = ARVideoCropGeometry(naturalSize: CGSize(width: 1001, height: 2001), preferredTransform: .identity, normalizedRect: CGRect(x: 0, y: 0, width: 1, height: 1))!
        assert(odd.size == CGSize(width: 1000, height: 2000))
        assert(ARVideoCropGeometry(naturalSize: CGSize(width: 100, height: 100), preferredTransform: .identity, normalizedRect: .zero) == nil)
        assert(ARVideoCropGeometry(naturalSize: .zero, preferredTransform: .identity, normalizedRect: crop) == nil)
        print("Video crop checks passed: portrait, rotated landscape, even dimensions, invalid regions")
    }
}
