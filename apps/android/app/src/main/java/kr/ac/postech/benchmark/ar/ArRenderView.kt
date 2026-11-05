package kr.ac.postech.benchmark.ar

import android.content.Context
import android.view.MotionEvent
import androidx.activity.ComponentActivity
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.ar.core.*
import io.github.sceneview.SceneView
import io.github.sceneview.ar.camera.ARCameraStream
import io.github.sceneview.ar.node.ARCameraNode
import io.github.sceneview.ar.node.AnchorNode
import io.github.sceneview.ar.light.LightEstimator
import io.github.sceneview.ar.scene.PlaneRenderer
import io.github.sceneview.math.Direction
import io.github.sceneview.node.LightNode
import java.util.concurrent.Executors
import kotlin.math.pow

/** Owns one session; rendering lifecycle is separate from camera permission/install UI. */
class ArRenderView(context: Context, activity: ComponentActivity) :
    SceneView(context, sharedActivity = activity) {
    private val arCamera = ARCameraNode(engine)
    private val cameraStream = ARCameraStream(materialLoader)
    private val depthOcclusion = DepthOcclusion(cameraStream)
    private val planes = PlaneRenderer(engine, modelLoader, materialLoader, scene)
    private val estimator = LightEstimator(engine, environmentLoader.iblPrefilter)
    private val environmentLight = LightNode(engine, LightManager.Type.DIRECTIONAL) {
        intensity(100_000f); direction(0f, -1f, -1f); castShadows(true)
    }
    private val manualLight = LightNode(engine, LightManager.Type.DIRECTIONAL) {
        intensity(0f); direction(0f, -1f, -1f); castShadows(true)
    }
    private var estimatedIndirect: IndirectLight? = null
    private var lastLightUpdate = 0L
    private var lastRotation = -1
    var arSession: Session? = null
        private set
    var latestFrame: Frame? = null
        private set
    var running = false
        private set
    var depthSupported = false
        private set
    var settings = ArSettings()
        set(value) { field = value; applySettings() }
    var frameListener: ((Frame) -> Unit)? = null
    var failureListener: ((Exception) -> Unit)? = null
    var tapListener: ((MotionEvent) -> Unit)? = null
    private var released = false

    init {
        planes.viewSize = android.util.Size(1, 1)
        skybox = null
        setCameraNode(arCamera)
        arCamera.setExposure(16f, 1f / 125f, 100f)
        cameraManipulator = null
        mainLightNode = environmentLight
        addChildNode(manualLight)
        scene.addEntity(cameraStream.entity)
        // Consume touch input so built-in orbit/drag gestures cannot move the AR camera or model.
        val detector = android.view.GestureDetector(context, object : android.view.GestureDetector.SimpleOnGestureListener() {
            override fun onDown(e: MotionEvent) = true
            override fun onSingleTapUp(e: MotionEvent): Boolean { tapListener?.invoke(e); return true }
        })
        onTouchEvent = { event, _ -> detector.onTouchEvent(event); true }
    }

    fun resumeSession() {
        if (released || running) return
        try {
            val session = arSession ?: Session(context).also { session ->
                try {
                    depthSupported = session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
                    session.configure(Config(session).apply {
                        planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                        focusMode = Config.FocusMode.AUTO
                        updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                        lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
                        depthMode = if (depthSupported) Config.DepthMode.AUTOMATIC else Config.DepthMode.DISABLED
                    })
                    session.setCameraTextureNames(cameraStream.cameraTextureIds)
                    arSession = session
                } catch (error: Exception) {
                    closeSession(session)
                    throw error
                }
            }
            if (width > 0 && height > 0) session.setDisplayGeometry(display?.rotation ?: 0, width, height)
            session.resume()
            running = true
            applySettings()
        } catch (error: Exception) { failureListener?.invoke(error) }
    }

    fun pauseSession() {
        if (!running) return
        running = false
        latestFrame = null
        arSession?.pause()
    }

    private fun applySettings() {
        estimatedIndirect?.intensity = 30_000f * 2f.pow(settings.exposure)
        if (!settings.depth || !depthSupported) depthOcclusion.useFlat()
        planes.isShadowReceiver = settings.shadows
        manualLight.intensity = if (settings.directLight) settings.intensity else 0f
        val direction = lightDirection(settings.azimuth, settings.elevation)
        manualLight.lightDirection = Direction(direction[0], direction[1], direction[2])
        if (!settings.environment) {
            environmentLight.intensity = 0f
            indirectLight = null
        } else {
            environmentLight.intensity = 100_000f
            indirectLight = estimatedIndirect
        }
    }

    fun showPlanes(show: Boolean) { planes.isVisible = show }

    override fun onResized(width: Int, height: Int) {
        super.onResized(width, height)
        planes.viewSize = android.util.Size(width, height)
        if (width > 0 && height > 0) arSession?.setDisplayGeometry(display?.rotation ?: 0, width, height)
    }

    override fun onFrame(frameTimeNanos: Long) {
        if (running) {
            try {
                arSession?.let { session ->
                    val rotation = display?.rotation ?: 0
                    if (rotation != lastRotation && width > 0 && height > 0) {
                        session.setDisplayGeometry(rotation, width, height)
                        lastRotation = rotation
                    }
                    val frame = session.update()
                    latestFrame = frame
                    cameraStream.update(session, frame)
                    depthOcclusion.update(frame, settings.depth && depthSupported)
                    arCamera.update(session, frame)
                    planes.update(session, frame)
                    childNodes.filterIsInstance<AnchorNode>().forEach { it.update(session, frame) }
                    if (settings.environment && frameTimeNanos - lastLightUpdate > 100_000_000) {
                        lastLightUpdate = frameTimeNanos
                        estimator.update(session, frame, arCamera.camera)?.let { estimate ->
                            estimate.mainLightDirection?.let { environmentLight.lightDirection = it }
                            estimate.mainLightColor?.let { environmentLight.color = it }
                            estimate.mainLightIntensity?.let { environmentLight.intensity = 100_000f * it }
                            estimate.irradiance?.let { coefficients ->
                                val next = IndirectLight.Builder().irradiance(3, coefficients)
                                    .apply { estimate.reflections?.let { reflections(it) } }
                                    .intensity(30_000f * 2f.pow(settings.exposure)).build(engine)
                                indirectLight = next
                                estimatedIndirect?.let { engine.destroyIndirectLight(it) }
                                estimatedIndirect = next
                            }
                        }
                    }
                    frameListener?.invoke(frame)
                }
            } catch (error: Exception) {
                pauseSession()
                failureListener?.invoke(error)
            }
        }
        super.onFrame(frameTimeNanos)
    }

    private fun closeSession(session: Session) {
        // ARCore close may block; the dedicated executor shuts down after this one operation.
        Executors.newSingleThreadExecutor().also { executor ->
            executor.execute { try { session.close() } finally { executor.shutdown() } }
        }
    }

    override fun destroy() {
        if (released) return
        released = true
        pauseSession()
        frameListener = null
        tapListener = null
        val session = arSession
        arSession = null
        session?.let { closeSession(it) }
        scene.removeEntity(cameraStream.entity)
        depthOcclusion.destroy()
        cameraStream.destroy()
        planes.destroy()
        indirectLight = null
        estimatedIndirect?.let { engine.destroyIndirectLight(it) }
        estimator.destroy()
        removeChildNode(manualLight)
        manualLight.destroy()
        mainLightNode = null
        environmentLight.destroy()
        arCamera.destroy()
        super.destroy()
    }
}
