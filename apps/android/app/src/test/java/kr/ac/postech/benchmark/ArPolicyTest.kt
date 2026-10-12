package kr.ac.postech.benchmark

import kr.ac.postech.benchmark.ar.*
import org.junit.Assert.*
import org.junit.Test

class ArPolicyTest {
    @Test fun depthPackingHonorsPaddingAndTreatsUnknownAsFarAway() {
        val source = java.nio.ByteBuffer.wrap(byteArrayOf(1, 2, 0, 0, 99, 99, 3, 4, 5, 6))
        val packed = packDepth(source, 2, 2, 6, 2)
        val bytes = ByteArray(packed.remaining()); packed.get(bytes)
        assertArrayEquals(byteArrayOf(1, 2, -1, -1, 3, 4, 5, 6), bytes)
        assertEquals(0, source.position())
        assertThrows(IllegalArgumentException::class.java) { packDepth(source, 3, 2, 6, 2) }
    }
    @Test fun heightUsesVerticalExtentRatherThanLargestDimension() {
        assertEquals(0.5f, normalizedHeightScale(1f, 2f), 0.0001f)
        for (bad in listOf(0f, -1f, Float.NaN, Float.POSITIVE_INFINITY)) {
            assertThrows(IllegalArgumentException::class.java) { normalizedHeightScale(1f, bad) }
        }
    }
    @Test fun animationPauseAndBackgroundDoNotAdvanceTime() {
        val clock = MotionClock()
        clock.playing = true
        clock.tick(1_000_000_000L)
        assertEquals(1f, clock.tick(2_000_000_000L), 0.001f)
        clock.playing = false
        assertEquals(1f, clock.tick(10_000_000_000L), 0.001f)
        clock.suspend(); clock.playing = true
        assertEquals(1f, clock.tick(30_000_000_000L), 0.001f)
        assertEquals(2f, clock.tick(31_000_000_000L), 0.001f)
        clock.reset(); assertEquals(0f, clock.seconds, 0.001f)
    }
    @Test fun recordingDimensionsAreEvenBoundedAndKeepPortraitOrLandscape() {
        assertEquals(720 to 1280, recordingSize(1080, 1920))
        assertEquals(1280 to 720, recordingSize(1920, 1080))
        assertEquals(400 to 872, recordingSize(401, 873))
        assertThrows(IllegalArgumentException::class.java) { recordingSize(0, 1080) }
    }
    @Test fun directionalLightPointsTowardGround() {
        val straightDown = lightDirection(0f, 90f)
        assertEquals(-1f, straightDown[1], 0.0001f)
        val diagonal = lightDirection(45f, 45f)
        assertEquals(1f, diagonal.sumOf { (it * it).toDouble() }.toFloat(), 0.0001f)
        assertTrue(diagonal[1] < 0f)
    }
}
