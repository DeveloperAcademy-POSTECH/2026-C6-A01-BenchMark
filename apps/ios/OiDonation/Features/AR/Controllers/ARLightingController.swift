import RealityKit

@MainActor
final class ARLightingController {
    private let sun = DirectionalLight()
    private var previous: Configuration?

    private struct Configuration: Equatable {
        let environment, shadow, occlusion, direct, mesh: Bool
        let exposure, intensity, azimuth, elevation: Float
        init(_ settings: ARCaptureSettings, mesh: Bool) {
            environment = settings.environmentLight; shadow = settings.groundingShadow
            occlusion = settings.sceneOcclusion; direct = settings.directLight; self.mesh = mesh
            exposure = settings.exposure; intensity = settings.intensity
            azimuth = settings.azimuth; elevation = settings.elevation
        }
    }

    func install(in view: RealityKit.ARView) {
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(sun)
        view.scene.addAnchor(anchor)
    }

    func apply(_ settings: ARCaptureSettings, to view: RealityKit.ARView, meshSupported: Bool) {
        let configuration = Configuration(settings, mesh: meshSupported)
        guard configuration != previous else { return }
        defer { previous = configuration }
        if settings.environmentLight { view.renderOptions.remove(.disableAREnvironmentLighting) }
        else { view.renderOptions.insert(.disableAREnvironmentLighting) }
        if settings.groundingShadow { view.renderOptions.remove(.disableGroundingShadows) }
        else { view.renderOptions.insert(.disableGroundingShadows) }
        view.environment.lighting.intensityExponent = settings.exposure
        if settings.sceneOcclusion && meshSupported { view.environment.sceneUnderstanding.options.insert(.occlusion) }
        else { view.environment.sceneUnderstanding.options.remove(.occlusion) }
        if meshSupported && settings.groundingShadow { view.environment.sceneUnderstanding.options.insert(.receivesLighting) }
        else { view.environment.sceneUnderstanding.options.remove(.receivesLighting) }
        sun.isEnabled = settings.directLight
        sun.light.intensity = settings.intensity
        if previous?.shadow != settings.groundingShadow {
            sun.shadow = settings.groundingShadow ? DirectionalLightComponent.Shadow() : nil
        }
        let az = settings.azimuth * .pi / 180
        let el = settings.elevation * .pi / 180
        let direction = SIMD3<Float>(cos(el) * sin(az), sin(el), cos(el) * cos(az))
        sun.look(at: .zero, from: direction * 10, relativeTo: nil)
    }
}
