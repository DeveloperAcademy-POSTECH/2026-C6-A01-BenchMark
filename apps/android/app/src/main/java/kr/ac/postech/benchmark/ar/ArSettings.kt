package kr.ac.postech.benchmark.ar

import android.os.Parcelable
import kotlinx.parcelize.Parcelize
import kotlin.math.cos
import kotlin.math.sin

enum class ArCharacter(val title: String, val asset: String) {
    NEOPJUK("넙죽이", "neopjuk"), PONIX("포닉스", "ponix"),
    PAIR("포닉스와 넙죽이", "ponixVsNeopjuk"), DONI("도니", "doni"),
    ANIMATED("넙죽이 · 애니메이션", "neopjukAnimated")
}

@Parcelize
data class ArSettings(
    val character: ArCharacter = ArCharacter.NEOPJUK,
    val height: Float = 1.2f,
    val rotation: Float = 0f,
    val floorOffset: Float = 0f,
    val environment: Boolean = true,
    val exposure: Float = 0f,
    val shadows: Boolean = true,
    val depth: Boolean = true,
    val directLight: Boolean = false,
    val intensity: Float = 50_000f,
    val azimuth: Float = 45f,
    val elevation: Float = 45f
) : Parcelable

// The light direction points from the source towards the ground, in AR coordinates.
fun lightDirection(azimuth: Float, elevation: Float): FloatArray {
    val az = Math.toRadians(azimuth.toDouble())
    val el = Math.toRadians(elevation.toDouble())
    return floatArrayOf((-cos(el) * sin(az)).toFloat(), -sin(el).toFloat(), (-cos(el) * cos(az)).toFloat())
}

fun normalizedHeightScale(height: Float, modelHeight: Float): Float {
    require(height.isFinite() && height > 0 && modelHeight.isFinite() && modelHeight > 0.0001f)
    return height / modelHeight
}

/** A paused animation retains its exact position and excludes time spent in the background. */
class MotionClock {
    var seconds = 0f
        private set
    var playing = false
    private var previous: Long? = null
    fun reset() { seconds = 0f; previous = null; playing = false }
    fun suspend() { previous = null }
    fun tick(nanos: Long): Float {
        previous?.let { if (playing) seconds += ((nanos - it).coerceAtLeast(0) / 1_000_000_000.0).toFloat() }
        previous = nanos
        return seconds
    }
}
