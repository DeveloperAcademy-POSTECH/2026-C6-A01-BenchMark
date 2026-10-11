import Observation
import RealityKit

@MainActor @Observable
final class ARAnimationController {
    struct Motion: Identifiable {
        let id: Int
        let title: String
        let entity: Entity
        let resource: AnimationResource
    }
    var motions: [Motion] = []
    var selectedMotion: Int?
    var motionPlaying = false
    private var playback: AnimationPlaybackController?
    func stop() { playback?.stop(); playback = nil; motionPlaying = false }

    func load(from model: Entity) {
        playback?.stop()
        playback = nil
        selectedMotion = nil
        motionPlaying = false
        motions = []
        collectMotions(from: model)
    }

    private func collectMotions(from entity: Entity) {
        // 부모 리소스에 자식의 애니메이션 트랙이 포함될 수 있으므로 중복 재생을 방지합니다.
        if !entity.availableAnimations.isEmpty {
            for animation in entity.availableAnimations {
                let index = motions.count
                let name = animation.name ?? ""
                motions.append(Motion(id: index, title: name.isEmpty ? "동작 \(index + 1)" : name,
                                      entity: entity, resource: animation))
            }
        } else {
            for child in entity.children { collectMotions(from: child) }
        }
    }

    func playMotion(_ id: Int) {
        guard let motion = motions.first(where: { $0.id == id }) else { return }
        playback?.stop()
        playback = motion.entity.playAnimation(motion.resource.repeat(duration: .infinity), transitionDuration: 0.2)
        selectedMotion = id
        motionPlaying = true
    }

    func toggleMotion() {
        guard let playback else { return }
        if motionPlaying { playback.pause() } else { playback.resume() }
        motionPlaying.toggle()
    }

}
