package kr.ac.postech.benchmark.ar

import android.Manifest
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.PixelCopy
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.lifecycleScope
import com.google.ar.core.ArCoreApk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class ArCameraActivity : ComponentActivity() {
    private var gate by mutableStateOf("카메라와 AR 지원 여부를 확인합니다.")
    private var controller by mutableStateOf<ArController?>(null)
    private var capture by mutableStateOf<ArCapture?>(null)
    private var saving by mutableStateOf(false)
    private var saved by mutableStateOf(false)
    private var recording by mutableStateOf(false)
    private var pendingVideo by mutableStateOf(false)
    private var renderView: ArRenderView? = null
    private var recorder: ArRecorder? = null
    private lateinit var store: CaptureStore
    private var initialSettings = ArSettings()
    private var installRequested = false
    private var checking = false
    private var previousOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    private var pendingDocument: ArCapture? = null
    private val cameraPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) checkAvailability() else gate = "카메라 권한이 거부되었습니다. 다시 허용하거나 앱 설정에서 변경해 주세요."
    }
    private val microphonePermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) pendingVideo = true else controller?.error = "음성 포함 영상에는 마이크 권한이 필요합니다. 사진 촬영은 사용할 수 있습니다."
    }
    private val createDocument = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val current = pendingDocument
        pendingDocument = null
        if (result.resultCode == RESULT_OK && current != null) result.data?.data?.let { uri ->
            saving = true
            lifecycleScope.launch {
                try {
                    withContext(Dispatchers.IO) {
                        checkNotNull(contentResolver.openOutputStream(uri)).use { out -> current.file.inputStream().use { it.copyTo(out) } }
                    }
                    saved = true
                } catch (error: Exception) { controller?.error = "저장 실패: ${error.localizedMessage}" }
                finally { saving = false }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        store = CaptureStore(this)
        @Suppress("DEPRECATION")
        savedInstanceState?.getParcelable<ArSettings>("arSettings")?.let { initialSettings = it }
        savedInstanceState?.getString("capture")?.let { path ->
            val file = File(filesDir, "captures/$path")
            val metadata = File(file.parentFile, "${file.nameWithoutExtension}.json")
            if (file.exists() && metadata.exists()) capture = ArCapture(file, metadata)
        }
        saved = savedInstanceState?.getBoolean("saved") ?: false
        if (savedInstanceState?.getBoolean("documentPending") == true) pendingDocument = capture
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    val current = controller
                    if (current == null) ArGate(gate, { requestCamera() }, {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                    }, { finish() })
                    else CameraContent(current)
                }
            }
        }
    }

    private fun requestCamera() {
        installRequested = false
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) checkAvailability()
        else cameraPermission.launch(Manifest.permission.CAMERA)
    }

    private fun checkAvailability() {
        if (checking || controller != null || isFinishing || isDestroyed) return
        checking = true
        gate = "AR 지원 여부 확인 중…"
        ArCoreApk.getInstance().checkAvailabilityAsync(this) { availability ->
            checking = false
            if (isDestroyed || isFinishing || controller != null) return@checkAvailabilityAsync
            when {
                availability.isSupported -> installAndOpen()
                availability.isTransient || availability.isUnknown -> gate = "AR 지원 여부를 확인하지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요."
                else -> gate = "이 기기는 ARCore를 지원하지 않습니다. 다른 앱 기능은 계속 사용할 수 있습니다."
            }
        }
    }

    private fun installAndOpen() {
        if (!lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            gate = "카메라 권한을 허용해 주세요."
            return
        }
        try {
            when (ArCoreApk.getInstance().requestInstall(this, !installRequested)) {
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> { installRequested = true; gate = "Google Play Services for AR 설치 후 돌아오세요." }
                ArCoreApk.InstallStatus.INSTALLED -> {
                    val view = ArRenderView(this, this)
                    view.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
                        if (recording && (right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop)) stopVideo()
                    }
                    renderView = view
                    controller = ArController(view, lifecycleScope, initialSettings)
                    recorder = ArRecorder(view, store)
                    controller?.resume()
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            }
        } catch (error: Exception) { gate = "AR 시작 실패: ${error.localizedMessage ?: error.javaClass.simpleName}" }
    }

    override fun onResume() {
        super.onResume()
        controller?.resume()
        if (controller == null && ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) checkAvailability()
    }

    override fun onPause() {
        if (recording) stopVideo()
        controller?.pause()
        super.onPause()
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putParcelable("arSettings", controller?.settings ?: initialSettings)
        outState.putString("capture", capture?.file?.name)
        outState.putBoolean("saved", saved)
        outState.putBoolean("documentPending", pendingDocument != null)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        recorder?.discard()
        controller?.destroy()
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onDestroy()
    }

    private fun metadata(current: ArController) = store.metadata(current.settings, current.motions.getOrNull(current.motion), current.depthSupported)

    private fun takePhoto() {
        val current = controller ?: return
        val view = renderView ?: return
        if (!current.canCapture || view.width < 2 || view.height < 2) return
        current.busy = true
        val record = metadata(current)
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        try {
            PixelCopy.request(view, bitmap, { status ->
                if (isDestroyed) { bitmap.recycle(); return@request }
                lifecycleScope.launch {
                    try {
                        check(status == PixelCopy.SUCCESS) { "카메라 프레임 복사 실패 ($status)" }
                        capture = withContext(Dispatchers.IO) { store.writePhoto(bitmap, record) }
                        saved = false
                    } catch (error: Exception) { current.error = "사진 촬영 실패: ${error.localizedMessage}" }
                    finally { bitmap.recycle(); current.busy = false }
                }
            }, Handler(Looper.getMainLooper()))
        } catch (error: Exception) { bitmap.recycle(); current.busy = false; current.error = "사진 촬영 실패: ${error.localizedMessage}" }
    }

    private fun requestVideo() {
        if (controller?.canCapture != true) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) startVideo()
        else microphonePermission.launch(Manifest.permission.RECORD_AUDIO)
    }

    private fun startVideo() {
        val current = controller ?: return
        if (!current.canCapture || !lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) return
        previousOrientation = requestedOrientation
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
        try {
            recorder?.start(metadata(current), { stopVideo() }, { message ->
                recorder?.discard(); recording = false; current.busy = false
                requestedOrientation = previousOrientation
                current.error = message
            })
            current.busy = true; recording = true
        } catch (error: Exception) {
            requestedOrientation = previousOrientation
            current.error = "녹화 시작 실패: ${error.localizedMessage}"
        }
    }

    private fun stopVideo() {
        if (!recording) return
        recording = false
        try { capture = recorder?.stop(); saved = false }
        catch (error: Exception) { controller?.error = "녹화 저장 실패: ${error.localizedMessage}" }
        finally { controller?.busy = false; requestedOrientation = previousOrientation }
    }

    private fun saveCapture(current: ArCapture) {
        if (saving || saved) return
        if (android.os.Build.VERSION.SDK_INT < 29) {
            pendingDocument = current
            createDocument.launch(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                type = current.mime; addCategory(Intent.CATEGORY_OPENABLE); putExtra(Intent.EXTRA_TITLE, "BenchMark-${current.file.name}")
            })
        } else {
            saving = true
            lifecycleScope.launch {
                try { withContext(Dispatchers.IO) { store.saveToGallery(current) }; saved = true }
                catch (error: Exception) { controller?.error = "갤러리 저장 실패: ${error.localizedMessage}" }
                finally { saving = false }
            }
        }
    }

    @Composable
    private fun CameraContent(current: ArController) {
        val view = renderView ?: return
        LaunchedEffect(current.tracking, recording, pendingVideo) {
            if (recording && !current.tracking) stopVideo()
            if (pendingVideo && current.canCapture) { pendingVideo = false; startVideo() }
        }
        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton({ finish() }, enabled = !saving && !current.busy) { Text("돌아가기") }
                Text(if (recording) "● 녹화 중 · 최대 60초" else "AR 카메라", Modifier.padding(12.dp))
            }
            AndroidView(factory = { view }, modifier = Modifier.fillMaxWidth().weight(1f))
            // Fixed control region: recording never changes the camera viewport or aspect ratio.
            Column(Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(current.message)
                if (current.loading) { LinearProgressIndicator(Modifier.fillMaxWidth()); Text("캐릭터 불러오는 중…") }
                current.error?.let { message ->
                    Text(message, color = MaterialTheme.colorScheme.error)
                    TextButton({ current.error = null; current.retryModel(); current.resume() }, enabled = !current.busy) { Text("다시 시도") }
                    TextButton({ startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))) }, enabled = !current.busy) { Text("앱 권한 설정") }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button({ takePhoto() }, enabled = current.canCapture && !saving) { Text("사진 촬영") }
                    Button({ if (recording) stopVideo() else requestVideo() }, enabled = recording || (current.canCapture && !saving)) {
                        Text(if (recording) "녹화 정지" else "영상 + 음성")
                    }
                }
                capture?.let { result ->
                    CaptureResult(result, saved, saving, !current.busy,
                        { saveCapture(result) }, {
                            try { startActivity(Intent.createChooser(store.share(result), "촬영 결과와 설정 공유")) }
                            catch (error: Exception) { current.error = "공유 실패: ${error.localizedMessage}" }
                        }, {
                            try { startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(store.uri(result.file), result.mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) }
                            catch (error: Exception) { current.error = "결과를 열 앱을 찾지 못했습니다. 저장 또는 공유를 이용해 주세요." }
                        })
                }
                ArControls(current)
            }
        }
    }
}

@Composable
fun ArGate(message: String, retry: () -> Unit, settings: () -> Unit, back: () -> Unit) {
    Column(Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("AR 카메라", style = MaterialTheme.typography.headlineSmall)
        Text(message)
        Button(retry) { Text("카메라 허용 및 다시 시도") }
        OutlinedButton(settings) { Text("앱 권한 설정") }
        TextButton(back) { Text("돌아가기") }
    }
}

@Composable
private fun CaptureResult(capture: ArCapture, saved: Boolean, saving: Boolean, enabled: Boolean, save: () -> Unit, share: () -> Unit, preview: () -> Unit) {
    val bitmap by produceState<Bitmap?>(null, capture.file) {
        value = null
        if (!capture.video) value = withContext(Dispatchers.IO) {
            android.graphics.BitmapFactory.decodeFile(capture.file.path, android.graphics.BitmapFactory.Options().apply { inSampleSize = 4 })
        }
    }
    bitmap?.let { Image(it.asImageBitmap(), "촬영한 AR 사진", Modifier.fillMaxWidth().height(160.dp)) }
    Text(if (saved) "저장 완료" else if (saving) "저장 중…" else if (capture.video) "영상 촬영 완료 · 음성 포함" else "사진 촬영 완료")
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TextButton(save, enabled = enabled && !saved && !saving) { Text("저장") }
        TextButton(share, enabled = enabled && !saving) { Text("공유") }
        TextButton(preview, enabled = enabled && !saving) { Text("크게 보기") }
    }
}
