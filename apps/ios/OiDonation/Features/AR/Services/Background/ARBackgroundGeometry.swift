import CoreGraphics

/// Shared by Vision input, hit testing and the rendered preview. All normalized
/// screen points use a top-left origin; Core Image uses a bottom-left origin.
nonisolated enum ARBackgroundGeometry {
    static func cameraToAnalysis(imageSize: CGSize, analysisSize: CGSize,
                                 displayTransform: CGAffineTransform) -> CGAffineTransform {
        CGAffineTransform(scaleX: 1 / imageSize.width, y: 1 / imageSize.height)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1))
            .concatenating(displayTransform)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1))
            .concatenating(CGAffineTransform(scaleX: analysisSize.width, y: analysisSize.height))
    }

    static func analysisSize(for viewport: CGSize) -> CGSize {
        let scale = 512 / max(viewport.width, viewport.height)
        return CGSize(width: max(1, (viewport.width * scale).rounded()),
                      height: max(1, (viewport.height * scale).rounded()))
    }

    /// Clear depth is exactly 0 (reversed Z) or 1 (forward Z). The infinite
    /// limit is only used to identify the convention; finite far planes can
    /// give limits slightly outside [0, 1], so it must not be used directly.
    static func clearDepth(projectionZ: Float, projectionW: Float) -> Float {
        guard abs(projectionW) > 0.00001 else { return 0 }
        return projectionZ / projectionW > 0.5 ? 1 : 0
    }

    /// Center aspect-fill, identical in the shader for portrait and landscape.
    static func backgroundScale(image: CGSize, viewport: CGSize) -> CGSize {
        let sourceAspect = image.width / image.height
        let viewAspect = viewport.width / viewport.height
        return sourceAspect > viewAspect
            ? CGSize(width: viewAspect / sourceAspect, height: 1)
            : CGSize(width: 1, height: sourceAspect / viewAspect)
    }
}
