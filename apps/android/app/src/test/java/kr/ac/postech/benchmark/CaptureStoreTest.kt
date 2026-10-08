package kr.ac.postech.benchmark

import android.graphics.Bitmap
import androidx.test.core.app.ApplicationProvider
import android.content.Context
import kr.ac.postech.benchmark.ar.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CaptureStoreTest {
    @Test fun photoAndMetadataAreRealFilesWithScopedShareUris() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val store = CaptureStore(context)
        val settings = ArSettings(character = ArCharacter.ANIMATED, height = 1.7f, depth = true)
        val record = store.metadata(settings, "spin", depthSupported = false)
        val bitmap = Bitmap.createBitmap(32, 48, Bitmap.Config.ARGB_8888)
        val capture = store.writePhoto(bitmap, record)
        try {
            assertTrue(capture.file.length() > 0)
            assertEquals(record, capture.metadata.readText())
            assertFalse(JSONObject(record).getBoolean("depthEnabled"))
            assertEquals("neopjukAnimated", JSONObject(record).getString("character"))
            assertEquals("content", store.uri(capture.file).scheme)
            assertEquals(2, store.share(capture).clipData!!.itemCount)
            assertFalse(capture.video)
        } finally { bitmap.recycle(); capture.file.delete(); capture.metadata.delete() }
    }
}
