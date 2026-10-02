package kr.ac.postech.benchmark.ar

import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import androidx.core.content.FileProvider
import org.json.JSONObject
import java.io.File
import java.util.UUID
import kotlin.math.roundToInt

data class ArCapture(val file: File, val metadata: File) {
    val video get() = file.extension == "mp4"
    val mime get() = if (video) "video/mp4" else "image/jpeg"
}

fun recordingSize(width: Int, height: Int): Pair<Int, Int> {
    require(width >= 2 && height >= 2)
    val factor = minOf(1f, 1280f / maxOf(width, height))
    return ((width * factor).roundToInt() / 2 * 2).coerceAtLeast(2) to
        ((height * factor).roundToInt() / 2 * 2).coerceAtLeast(2)
}

class CaptureStore(private val context: Context) {
    private val directory get() = File(context.filesDir, "captures").apply { check(isDirectory || mkdirs()) }
    fun newFile(extension: String) = File(directory, "${UUID.randomUUID()}.$extension")

    fun metadata(settings: ArSettings, motion: String?, depthSupported: Boolean): String = JSONObject().apply {
        put("schema", 1); put("platform", "android"); put("sampledAtEpochMs", System.currentTimeMillis())
        put("character", settings.character.asset); put("heightMeters", settings.height)
        put("rotationDegrees", settings.rotation); put("floorOffsetMeters", settings.floorOffset)
        put("environmentLight", settings.environment); put("environmentExposureEV", settings.exposure); put("groundShadows", settings.shadows)
        put("depthSupported", depthSupported); put("depthEnabled", depthSupported && settings.depth)
        put("directLight", settings.directLight); put("intensityLux", settings.intensity)
        put("azimuthDegrees", settings.azimuth); put("elevationDegrees", settings.elevation)
        put("motion", motion ?: JSONObject.NULL)
        put("note", "Settings sampled at capture request; not a frame-synchronized sensor record.")
    }.toString(2)

    fun writePhoto(bitmap: Bitmap, metadata: String): ArCapture {
        val file = newFile("jpg")
        try {
            file.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.JPEG, 95, it)) { "JPEG 인코딩 실패" } }
            return finish(file, metadata)
        } catch (error: Exception) { file.delete(); throw error }
    }

    fun finish(file: File, metadata: String): ArCapture {
        val sidecar = File(file.parentFile, "${file.nameWithoutExtension}.json")
        try { sidecar.writeText(metadata); return ArCapture(file, sidecar) }
        catch (error: Exception) { sidecar.delete(); file.delete(); throw error }
    }

    fun uri(file: File): Uri = FileProvider.getUriForFile(context, "${context.packageName}.captures", file)

    fun share(capture: ArCapture): Intent {
        val uris = arrayListOf(uri(capture.file), uri(capture.metadata))
        return Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "*/*"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            clipData = ClipData.newUri(context.contentResolver, "AR capture", uris[0]).apply {
                addItem(ClipData.Item(uris[1]))
            }
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    @RequiresApi(29)
    fun saveToGallery(capture: ArCapture): Uri {
        val resolver = context.contentResolver
        val collection = if (capture.video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, "BenchMark-${capture.file.name}")
            put(MediaStore.MediaColumns.MIME_TYPE, capture.mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, if (capture.video) "Movies/BenchMark" else "Pictures/BenchMark")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = checkNotNull(resolver.insert(collection, values)) { "갤러리 파일 생성 실패" }
        try {
            checkNotNull(resolver.openOutputStream(uri)).use { output -> capture.file.inputStream().use { it.copyTo(output) } }
            check(resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null) == 1)
            return uri
        } catch (error: Exception) { resolver.delete(uri, null, null); throw error }
    }
}
