package kr.ac.postech.benchmark.ar

import androidx.compose.runtime.*
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.math.Position
import io.github.sceneview.math.Rotation
import io.github.sceneview.math.Scale
import io.github.sceneview.node.ModelNode
import io.github.sceneview.node.Node
import kotlinx.coroutines.*
import java.nio.ByteBuffer

class ArController(private val view: ArRenderView, private val scope: CoroutineScope, initial: ArSettings) {
    var settings by mutableStateOf(initial)
        private set
    var message by mutableStateOf("바닥을 천천히 비춰 주세요.")
    var error by mutableStateOf<String?>(null)
    var loading by mutableStateOf(false)
        private set
    var placed by mutableStateOf(false)
        private set
    var locked by mutableStateOf(false)
    var tracking by mutableStateOf(false)
        private set
    var depthSupported by mutableStateOf(false)
        private set
    var motions by mutableStateOf<List<String>>(emptyList())
        private set
    var motion by mutableIntStateOf(-1)
        private set
    var playing by mutableStateOf(false)
        private set
    var busy by mutableStateOf(false)
    val canCapture get() = placed && tracking && !loading && !busy && model != null
    private var anchor: AnchorNode? = null
    private val placement = Node(view.engine)
    private val normalization = Node(view.engine).apply { parent = placement }
    private val originOffset = Node(view.engine).apply { parent = normalization }
    private var model: ModelNode? = null
    private var loadJob: Job? = null
    private var disposed = false
    private val clock = MotionClock()

    init {
        view.settings = settings
        view.frameListener = { frame ->
            tracking = frame.camera.trackingState == TrackingState.TRACKING &&
                (anchor == null || anchor?.trackingState == TrackingState.TRACKING)
            depthSupported = view.depthSupported
            if (!tracking) {
                message = when (frame.camera.trackingFailureReason) {
                    com.google.ar.core.TrackingFailureReason.INSUFFICIENT_LIGHT -> "주변이 어둡습니다. 밝은 곳을 비춰 주세요."
                    com.google.ar.core.TrackingFailureReason.EXCESSIVE_MOTION -> "휴대폰을 천천히 움직여 주세요."
                    else -> "공간 추적 중 · 무늬가 있는 바닥을 천천히 비춰 주세요."
                }
            } else message = if (placed) "배치 완료 · ${if (locked) "위치 잠김" else "바닥을 터치하면 이동합니다"}" else "인식된 바닥을 터치해 캐릭터를 배치하세요."
            val time = clock.tick(frame.timestamp)
            model?.let { node ->
                if (motion in 0 until node.animationCount) {
                    val duration = node.animator.getAnimationDuration(motion)
                    node.animator.applyAnimation(motion, if (duration > 0) time % duration else 0f)
                    node.animator.updateBoneMatrices()
                }
            }
        }
        view.failureListener = { error = "AR 세션 오류: ${it.localizedMessage ?: it.javaClass.simpleName}"; tracking = false }
        view.tapListener = { event ->
            if (!loading && !busy && !locked && tracking) {
                try {
                    val hit = view.latestFrame?.hitTest(event)?.firstOrNull { result ->
                        val plane = result.trackable as? Plane
                        plane != null && plane.type == Plane.Type.HORIZONTAL_UPWARD_FACING &&
                            plane.trackingState == TrackingState.TRACKING && plane.isPoseInPolygon(result.hitPose)
                    }
                    if (hit == null) message = "아직 바닥을 찾지 못했습니다. 다른 각도에서 비춰 주세요."
                    else {
                        val next = AnchorNode(view.engine, hit.createAnchor()).apply { isEditable = false }
                        placement.parent = null
                        anchor?.let { view.removeChildNode(it); it.destroy() }
                        anchor = next
                        placement.parent = next
                        view.addChildNode(next)
                        placed = true
                        view.showPlanes(false)
                    }
                } catch (failure: Exception) { error = "배치 실패: ${failure.localizedMessage}" }
            }
        }
        load(initial.character)
    }

    fun update(next: ArSettings) {
        if (busy) return
        val changed = settings.character != next.character
        settings = next
        view.settings = next
        applyTransform()
        if (changed) load(next.character)
    }

    fun retryModel() { if (!busy) load(settings.character) }

    private fun load(character: ArCharacter) {
        loadJob?.cancel()
        loading = true
        error = null
        loadJob = scope.launch {
            try {
                val bytes = withContext(Dispatchers.IO) {
                    view.context.assets.open("models/${character.asset}.glb").use { it.readBytes() }
                }
                ensureActive()
                if (disposed) return@launch
                // Filament operations stay on the UI thread; only asset I/O runs on Dispatchers.IO.
                releaseModel()
                val instance = view.modelLoader.createModelInstance(ByteBuffer.wrap(bytes))
                try {
                    val node = ModelNode(instance, autoAnimate = false).apply { isEditable = false }
                    model = node
                    node.parent = originOffset
                    val height = node.extents.y
                    normalization.scale = Scale(normalizedHeightScale(1f, height))
                    originOffset.position = Position(-node.center.x, -(node.center.y - node.halfExtent.y), -node.center.z)
                    motions = (0 until node.animationCount).map { node.animator.getAnimationName(it).ifBlank { "동작 ${it + 1}" } }
                    node.setScreenSpaceContactShadows(true)
                    applyTransform()
                } catch (failure: Exception) {
                    if (model == null) view.modelLoader.destroyModel(instance.asset)
                    else releaseModel()
                    throw failure
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (failure: Exception) { error = "캐릭터 로딩 실패: ${failure.localizedMessage}" }
            finally { if (isActive && !disposed) loading = false }
        }
    }

    private fun applyTransform() {
        placement.scale = Scale(settings.height)
        placement.rotation = Rotation(0f, settings.rotation, 0f)
        placement.position = Position(0f, settings.floorOffset, 0f)
        model?.isShadowCaster = settings.shadows
    }

    fun selectMotion(index: Int) {
        if (busy || index !in motions.indices) return
        clock.reset(); clock.playing = true
        motion = index; playing = true
    }

    fun toggleMotion() {
        if (busy || motion < 0) return
        playing = !playing
        clock.playing = playing
    }

    fun resetPlacement() {
        if (busy) return
        placement.parent = null
        anchor?.let { view.removeChildNode(it); it.destroy() }
        anchor = null
        placed = false; locked = false
        view.showPlanes(true)
    }

    fun pause() { clock.suspend(); tracking = false; view.pauseSession() }
    fun resume() { clock.suspend(); view.resumeSession() }

    private fun releaseModel() {
        model?.let { node ->
            node.parent = null
            // gltfio owns all model entities. Destroy through its loader exactly once.
            view.modelLoader.destroyModel(node.model)
        }
        model = null
        motions = emptyList(); motion = -1; playing = false; clock.reset()
    }

    fun destroy() {
        if (disposed) return
        disposed = true
        loadJob?.cancel()
        busy = false
        resetPlacement()
        releaseModel()
        originOffset.destroy()
        normalization.destroy()
        placement.destroy()
        view.destroy()
    }
}
