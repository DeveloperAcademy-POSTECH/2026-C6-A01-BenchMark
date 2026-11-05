package kr.ac.postech.benchmark.ar

import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Build
import android.view.Surface
import java.io.File

/** Records only the composited render surface, excluding Compose controls. */
class ArRecorder(private val view: io.github.sceneview.SceneView, private val store: CaptureStore) {
    private var recorder: MediaRecorder? = null
    private var surface: Surface? = null
    private var output: File? = null
    private var metadata = ""
    val isRecording get() = recorder != null

    fun start(record: String, onLimit: () -> Unit, onError: (String) -> Unit) {
        check(recorder == null)
        val (width, height) = recordingSize(view.width, view.height)
        val file = store.newFile("mp4")
        @Suppress("DEPRECATION")
        val next = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(view.context) else MediaRecorder()
        try {
            next.setAudioSource(MediaRecorder.AudioSource.MIC)
            next.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            next.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            next.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            next.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            next.setVideoSize(width, height)
            next.setVideoFrameRate(30)
            next.setVideoEncodingBitRate(8_000_000)
            next.setAudioEncodingBitRate(128_000)
            next.setAudioSamplingRate(44_100)
            next.setMaxDuration(60_000)
            next.setOutputFile(file.absolutePath)
            next.setOnInfoListener { _, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) onLimit()
            }
            next.setOnErrorListener { _, what, extra -> onError("녹화 오류 ($what/$extra)") }
            next.prepare()
            surface = next.surface
            view.startMirroring(checkNotNull(surface), width = width, height = height)
            next.start()
            recorder = next; output = file; metadata = record
        } catch (error: Exception) {
            surface?.let { view.stopMirroring(it); it.release() }
            surface = null
            next.release(); file.delete()
            throw error
        }
    }

    fun stop(): ArCapture {
        val active = checkNotNull(recorder)
        val file = checkNotNull(output)
        recorder = null; output = null
        try {
            surface?.let { view.stopMirroring(it); view.engine.flushAndWait() }
            active.stop()
        } catch (error: Exception) {
            file.delete()
            throw error
        } finally {
            surface?.release(); surface = null
            active.release()
        }
        try {
            // Require both encoded tracks before reporting recording success.
            val extractor = MediaExtractor()
            try {
                extractor.setDataSource(file.absolutePath)
                val formats = (0 until extractor.trackCount).map { extractor.getTrackFormat(it) }
                check(formats.any { it.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true }) { "영상 트랙이 없습니다." }
                check(formats.any { it.getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true }) { "음성 트랙이 없습니다." }
            } finally { extractor.release() }
            return store.finish(file, metadata)
        } catch (error: Exception) { file.delete(); throw error }
    }

    fun discard() {
        val active = recorder ?: return
        recorder = null
        try { surface?.let { view.stopMirroring(it); view.engine.flushAndWait() } }
        finally {
            surface?.release(); surface = null
            // release() also stops native recording, including an errored recorder.
            active.release()
            output?.delete(); output = null
        }
    }
}
