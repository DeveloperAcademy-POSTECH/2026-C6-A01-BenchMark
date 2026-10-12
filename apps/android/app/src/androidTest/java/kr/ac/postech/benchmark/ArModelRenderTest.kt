package kr.ac.postech.benchmark

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import io.github.sceneview.SceneView
import io.github.sceneview.math.Position
import io.github.sceneview.math.Scale
import io.github.sceneview.node.Node
import kr.ac.postech.benchmark.ar.ArRenderView
import io.github.sceneview.node.ModelNode
import kr.ac.postech.benchmark.ar.ArCharacter
import org.junit.Assert.*
import org.junit.Test
import org.junit.Rule
import androidx.test.rule.GrantPermissionRule
import kr.ac.postech.benchmark.ar.ArRecorder
import kr.ac.postech.benchmark.ar.CaptureStore
import kr.ac.postech.benchmark.ar.ArSettings
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** GPU asset smoke test. This does not claim to exercise ARCore tracking or a real camera. */
@RunWith(AndroidJUnit4::class)
class ArModelRenderTest {
    @get:Rule val microphone = GrantPermissionRule.grant(android.Manifest.permission.RECORD_AUDIO)
    @Test fun arRenderSurfaceReleasesNativeResourcesWithoutStartingCamera() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var view: ArRenderView
            scenario.onActivity { activity ->
                view = ArRenderView(activity, activity)
                activity.setContentView(view, android.view.ViewGroup.LayoutParams(480, 640))
                assertNull(view.arSession)
                assertFalse(view.running)
            }
            scenario.onActivity { view.destroy(); view.destroy() }
        }
    }

    @Test fun allModelsLoadRenderAndAnimatedModelHasPlayableMotion() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var scene: SceneView
            scenario.onActivity { activity ->
                scene = SceneView(activity, sharedActivity = activity)
                activity.setContentView(scene, android.view.ViewGroup.LayoutParams(480, 640))
                scene.cameraNode.position = Position(0f, 0.5f, 2.5f)
            }
            for (character in ArCharacter.entries) {
                lateinit var node: ModelNode
                lateinit var normalized: Node
                lateinit var offset: Node
                val rendered = CountDownLatch(1)
                scenario.onActivity {
                    val instance = scene.modelLoader.createModelInstance("models/${character.asset}.glb")
                    node = ModelNode(instance, autoAnimate = false)
                    scene.cameraNode.position = Position(0f, 0.5f, maxOf(2.5f, node.extents.x / node.extents.y * 2f))
                    normalized = Node(scene.engine).apply { scale = Scale(1f / node.extents.y) }
                    offset = Node(scene.engine).apply {
                        position = Position(-node.center.x, -(node.center.y - node.halfExtent.y), -node.center.z)
                        parent = normalized
                    }
                    node.parent = offset
                    scene.addChildNode(normalized)
                    assertTrue(node.extents.y > 0f)
                    if (character == ArCharacter.ANIMATED) {
                        assertTrue(node.animationCount > 0)
                        assertTrue(node.skinCount > 0)
                        node.animator.applyAnimation(0, 0.8f)
                        node.animator.updateBoneMatrices()
                    }
                    var frames = 0
                    scene.onFrame = { if (++frames >= 30) rendered.countDown() }
                }
                assertTrue("Renderer did not produce frames", rendered.await(30, TimeUnit.SECONDS))
                val copied = CountDownLatch(1)
                var status = -1
                lateinit var bitmap: Bitmap
                instrumentation.runOnMainSync {
                    scene.engine.flushAndWait()
                    bitmap = Bitmap.createBitmap(scene.width, scene.height, Bitmap.Config.ARGB_8888)
                    PixelCopy.request(scene, bitmap, { status = it; copied.countDown() }, Handler(Looper.getMainLooper()))
                }
                assertTrue(copied.await(10, TimeUnit.SECONDS))
                assertEquals(PixelCopy.SUCCESS, status)
                val file = File(instrumentation.targetContext.filesDir, "ar-verification/${character.asset}.png")
                file.parentFile!!.mkdirs()
                file.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
                val colors = mutableSetOf<Int>()
                for (y in 0 until bitmap.height step 12) for (x in 0 until bitmap.width step 12) colors += bitmap.getPixel(x, y)
                assertTrue("Model render must contain visible detail", colors.size > 30)
                bitmap.recycle()
                if (character == ArCharacter.ANIMATED) {
                    val store = CaptureStore(instrumentation.targetContext)
                    lateinit var recorder: ArRecorder
                    val videoFrames = CountDownLatch(1)
                    var videoError: String? = null
                    scenario.onActivity {
                        recorder = ArRecorder(scene, store)
                        recorder.start(store.metadata(ArSettings(character = character), "render-test", false), {}, { videoError = it })
                        var frames = 0
                        scene.onFrame = { if (++frames >= 90) videoFrames.countDown() }
                    }
                    try {
                        assertTrue(videoFrames.await(30, TimeUnit.SECONDS))
                        scenario.onActivity {
                            assertNull(videoError)
                            val result = recorder.stop()
                            assertTrue(result.video)
                            assertTrue(result.file.length() > 0)
                            result.file.copyTo(File(file.parentFile, "render-video.mp4"), overwrite = true)
                            result.file.delete(); result.metadata.delete()
                        }
                    } finally { scenario.onActivity { recorder.discard() } }
                }
                scenario.onActivity {
                    scene.onFrame = null
                    scene.removeChildNode(normalized)
                    node.parent = null
                    scene.modelLoader.destroyModel(node.model)
                    offset.destroy(); normalized.destroy()
                }
            }
        }
    }
}
