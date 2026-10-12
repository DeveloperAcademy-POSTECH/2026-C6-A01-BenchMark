package kr.ac.postech.benchmark.ar

import com.google.android.filament.Texture
import com.google.ar.core.Frame
import com.google.ar.core.exceptions.NotYetAvailableException
import io.github.sceneview.ar.camera.ARCameraStream
import io.github.sceneview.material.setTexture
import java.nio.ByteBuffer

/** Packs DEPTH16 respecting row/pixel strides; unknown depth must not hide virtual objects. */
fun packDepth(source: ByteBuffer, width: Int, height: Int, rowStride: Int, pixelStride: Int): ByteBuffer {
    require(width > 0 && height > 0 && pixelStride >= 2 && rowStride >= width * pixelStride)
    val base = source.position()
    require(base.toLong() + (height - 1L) * rowStride + (width - 1L) * pixelStride + 2 <= source.limit())
    return ByteBuffer.allocateDirect(width * height * 2).apply {
        for (y in 0 until height) for (x in 0 until width) {
            val offset = base + y * rowStride + x * pixelStride
            val low = source.get(offset)
            val high = source.get(offset + 1)
            if (low == 0.toByte() && high == 0.toByte()) { put(0xff.toByte()); put(0xff.toByte()) }
            else { put(low); put(high) }
        }
        flip()
    }
}

/** Owns the correctly sized texture instead of SceneView 2.3.0's default 1x1 depth texture. */
class DepthOcclusion(private val stream: ARCameraStream) {
    private var texture: Texture? = null
    private val engine get() = stream.engine

    fun update(frame: Frame, enabled: Boolean) {
        if (!enabled) { useFlat(); return }
        try {
            frame.acquireDepthImage16Bits().use { image ->
                val plane = image.planes[0]
                val data = packDepth(plane.buffer, image.width, image.height, plane.rowStride, plane.pixelStride)
                val current = texture?.takeIf { it.getWidth(0) == image.width && it.getHeight(0) == image.height }
                    ?: Texture.Builder().width(image.width).height(image.height).levels(1)
                        .sampler(Texture.Sampler.SAMPLER_2D).format(Texture.InternalFormat.RG8).build(engine).also { next ->
                            stream.depthOcclusionMaterial.defaultInstance.setTexture("depthTexture", next)
                            texture?.let { engine.destroyTexture(it) }
                            texture = next
                        }
                // The descriptor retains the copied buffer until Filament consumes it. The AR image
                // can close immediately, without retaining an ARCore image across frame boundaries.
                current.setImage(engine, 0, Texture.PixelBufferDescriptor(data, Texture.Format.RG, Texture.Type.UBYTE, 1))
                stream.setMaterialInstances(stream.depthOcclusionMaterial.defaultInstance)
            }
        } catch (_: NotYetAvailableException) { useFlat() }
    }

    fun useFlat() { stream.setMaterialInstances(stream.standardMaterial.defaultInstance) }

    fun destroy() {
        useFlat()
        stream.depthOcclusionMaterial.defaultInstance.setTexture("depthTexture", stream.depthTexture)
        texture?.let { engine.destroyTexture(it) }
        texture = null
    }
}
