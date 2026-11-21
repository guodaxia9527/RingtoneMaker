package com.ringtone.ringtone_maker

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.SystemClock
import android.os.Handler
import android.os.HandlerThread
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.sqrt

/** Raw 20 ms peak/energy envelopes, streamed before the full decode completes. */
object WaveformAnalyzer {
    private const val VERSION = 9
    private const val MAX_BINS = 360000

    fun analyze(context: Context, path: String, cancelled: () -> Boolean,
                progress: (Map<String, Any>) -> Unit): Map<String, Any> {
        val started = SystemClock.elapsedRealtime()
        fun check() {
            if (cancelled() || Thread.currentThread().isInterrupted) throw InterruptedException("操作已取消")
        }
        check()
        val key = AudioSourceAccess.fingerprint(context, path, cancelled)
        val cache = File(context.cacheDir, "envelope_v${VERSION}_$key.bin")
        if (cache.isFile) {
            runCatching {
                DataInputStream(cache.inputStream().buffered()).use { input ->
                    require(input.readInt() == VERSION)
                    val duration = input.readLong()
                    val gain = input.readDouble()
                    val count = input.readInt()
                    require(count in 1..MAX_BINS && duration > 0 && gain.isFinite() && gain > 0 &&
                        cache.length() == 24L + count * 8L)
                    val peaks = DoubleArray(count) { input.readFloat().toDouble() }
                    val rms = DoubleArray(count) { input.readFloat().toDouble() }
                    require(peaks.all { it.isFinite() && it >= 0 } && rms.all { it.isFinite() && it >= 0 })
                    check()
                    cache.setLastModified(System.currentTimeMillis())
                    android.util.Log.i("Waveform", "cacheHit bins=$count peak=${peaks.maxOrNull() ?: 0.0} rms=${rms.maxOrNull() ?: 0.0}")
                    return mapOf("peaks" to peaks, "rms" to rms, "durationMs" to duration / 1000,
                        "gain" to gain, "available" to count, "count" to count, "cacheHit" to true,
                        "elapsedMs" to SystemClock.elapsedRealtime() - started)
                }
            }.onFailure { if (it is InterruptedException) throw it else cache.delete() }
        }
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        var callbackThread: HandlerThread? = null
        val stopped = AtomicBoolean(false)
        try {
            AudioSourceAccess.open(extractor, context, path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("文件没有可解码音轨")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val duration = format.getLong(MediaFormat.KEY_DURATION).coerceAtLeast(1)
            val count = ceil(duration / 20000.0).toInt().coerceIn(1, MAX_BINS)
            val binUs = duration.toDouble() / count
            val peaks = DoubleArray(count)
            val squares = DoubleArray(count)
            val counts = IntArray(count)
            val rms = DoubleArray(count)
            var gain = 0.0
            var sent = 0
            var latestUs = 0L
            var lastSent = started
            fun publish(complete: Boolean = false): Map<String, Any> {
                val available = if (complete) count else (latestUs / binUs).toInt().coerceIn(sent, count)
                for (i in sent until available) rms[i] = if (counts[i] == 0) 0.0 else sqrt(squares[i] / counts[i])
                if (gain == 0.0) {
                    val sorted = rms.copyOf(available).apply { sort() }
                    val reference = if (sorted.isEmpty()) 0.0 else sorted[((sorted.size - 1) * .95).toInt()]
                    // Fixed after the initial six seconds: quiet pauses remain quiet,
                    // and the waveform never pumps as the playhead moves.
                    gain = .8 / max(.05, reference)
                }
                val result = mapOf("peaks" to peaks.copyOfRange(if (complete) 0 else sent, available),
                    "rms" to rms.copyOfRange(if (complete) 0 else sent, available),
                    "offset" to (if (complete) 0 else sent), "available" to available,
                    "count" to count, "durationMs" to duration / 1000, "gain" to gain,
                    "cacheHit" to false, "elapsedMs" to SystemClock.elapsedRealtime() - started)
                sent = available
                lastSent = SystemClock.elapsedRealtime()
                return result
            }
            val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            var rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            var inputDone = false
            var inputBuffers = 0
            var firstInputUs: Long? = null
            var inputBytes = 0L
            var outputBuffers = 0
            var outputBytes = 0L
            var outputFrames = 0L
            val done = CountDownLatch(1)
            val failure = AtomicReference<Exception?>(null)
            val lastActivity = AtomicLong(SystemClock.elapsedRealtime())
            var inputNs = 0L
            var measureNs = 0L
            val worker = HandlerThread("waveform-decoder").apply { start() }
            callbackThread = worker
            fun guarded(action: () -> Unit) {
                if (stopped.get()) return
                try {
                    check()
                    action()
                    lastActivity.set(SystemClock.elapsedRealtime())
                } catch (e: Exception) {
                    failure.compareAndSet(null, e)
                    stopped.set(true)
                    done.countDown()
                }
            }
            decoder.setCallback(object : MediaCodec.Callback() {
                override fun onInputBufferAvailable(codec: MediaCodec, index: Int) = guarded {
                    if (!inputDone) {
                        val began = System.nanoTime()
                        val buffer = codec.getInputBuffer(index)!!
                        buffer.clear()
                        val time = extractor.sampleTime
                        // AAC priming/edit lists may give real packets negative PTS.
                        // Only a failed sample read means end of stream.
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            if (firstInputUs == null) firstInputUs = time
                            inputBuffers++
                            inputBytes += size
                            codec.queueInputBuffer(index, 0, size, time, 0)
                            extractor.advance()
                        }
                        inputNs += System.nanoTime() - began
                    }
                }
                override fun onOutputFormatChanged(codec: MediaCodec, output: MediaFormat) = guarded {
                    rate = output.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = output.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    encoding = if (output.containsKey(MediaFormat.KEY_PCM_ENCODING))
                        output.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                }
                override fun onError(codec: MediaCodec, error: MediaCodec.CodecException) {
                    failure.compareAndSet(null, error)
                    stopped.set(true)
                    done.countDown()
                }
                override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) = guarded {
                    val began = System.nanoTime()
                    try {
                            outputBuffers++
                            outputBytes += info.size
                            val bytes = when (encoding) {
                                AudioFormat.ENCODING_PCM_8BIT -> 1
                                AudioFormat.ENCODING_PCM_16BIT -> 2
                                AudioFormat.ENCODING_PCM_24BIT_PACKED -> 3
                                AudioFormat.ENCODING_PCM_FLOAT, AudioFormat.ENCODING_PCM_32BIT -> 4
                                else -> error("不支持的 PCM 编码：$encoding")
                            }
                            val frames = info.size / (bytes * channels)
                            outputFrames += frames
                            if (frames > 0) {
                                val buffer = decoder.getOutputBuffer(index)!!.order(ByteOrder.LITTLE_ENDIAN)
                                buffer.limit(info.offset + info.size)
                                // Decode preroll, but display only samples at/after zero.
                                var frame = ceil(-info.presentationTimeUs.toDouble() * rate / 1000000)
                                    .toInt().coerceIn(0, frames)
                                buffer.position(info.offset + frame * bytes * channels)
                                while (frame < frames) {
                                    val time = info.presentationTimeUs + frame.toLong() * 1000000 / rate
                                    val bucket = (time / binUs).toInt().coerceIn(0, count - 1)
                                    val endFrame = ceil(((bucket + 1) * binUs - info.presentationTimeUs) * rate / 1000000)
                                        .toInt().coerceIn(frame + 1, frames)
                                    var peak = peaks[bucket]
                                    var square = squares[bucket]
                                    repeat((endFrame - frame) * channels) {
                                        val sample = when (encoding) {
                                            AudioFormat.ENCODING_PCM_16BIT -> buffer.short / 32768.0
                                            AudioFormat.ENCODING_PCM_FLOAT -> buffer.float.toDouble().let { if (it.isFinite()) it else 0.0 }
                                            AudioFormat.ENCODING_PCM_8BIT -> ((buffer.get().toInt() and 255) - 128) / 128.0
                                            AudioFormat.ENCODING_PCM_32BIT -> buffer.int / 2147483648.0
                                            else -> {
                                                val lo = buffer.get().toInt() and 255
                                                val mid = buffer.get().toInt() and 255
                                                val hi = buffer.get().toInt()
                                                ((hi shl 16) or (mid shl 8) or lo) / 8388608.0
                                            }
                                        }
                                        peak = max(peak, abs(sample))
                                        square += sample * sample
                                    }
                                    peaks[bucket] = peak
                                    squares[bucket] = square
                                    counts[bucket] += (endFrame - frame) * channels
                                    frame = endFrame
                                }
                                latestUs = max(latestUs, info.presentationTimeUs + frames.toLong() * 1000000 / rate)
                            }
                    } finally { codec.releaseOutputBuffer(index, false) }
                    measureNs += System.nanoTime() - began
                    if (latestUs >= 6000000 && (sent == 0 || SystemClock.elapsedRealtime() - lastSent >= 250)) {
                        progress(publish())
                    }
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                        stopped.set(true)
                        done.countDown()
                    }
                }
            }, Handler(worker.looper))
            decoder.configure(format, null, null, 0)
            decoder.start()
            while (!done.await(100, TimeUnit.MILLISECONDS)) {
                check()
                if (SystemClock.elapsedRealtime() - lastActivity.get() > 30000) error("Decoder timeout")
            }
            failure.get()?.let { throw it }
            check()
            // An empty decode is a failure, not a valid all-silent waveform.
            // Do not persist it and poison subsequent imports via the cache.
            check(counts.any { it > 0 }) { "未能解码出音频样本，请重新选择文件" }
            val result = publish(true) + mapOf("inputMs" to inputNs / 1000000, "measureMs" to measureNs / 1000000)
            android.util.Log.i("Waveform", "decodeMs=${SystemClock.elapsedRealtime() - started} inputMs=${inputNs / 1000000} measureMs=${measureNs / 1000000} mime=${format.getString(MediaFormat.KEY_MIME)} sampleRate=$rate channels=$channels pcm=$encoding bins=$count firstInputUs=$firstInputUs inputBuffers=$inputBuffers inputBytes=$inputBytes outputBuffers=$outputBuffers outputBytes=$outputBytes outputFrames=$outputFrames samples=${counts.sumOf { it.toLong() }} peak=${peaks.maxOrNull() ?: 0.0} rms=${rms.maxOrNull() ?: 0.0}")
            val temporary = File.createTempFile("envelope_", ".tmp", context.cacheDir)
            try {
                DataOutputStream(temporary.outputStream().buffered()).use { output ->
                    output.writeInt(VERSION)
                    output.writeLong(duration)
                    output.writeDouble(gain)
                    output.writeInt(count)
                    peaks.forEach { output.writeFloat(it.toFloat()) }
                    rms.forEach { output.writeFloat(it.toFloat()) }
                }
                check()
                temporary.renameTo(cache)
                // Bound only our own waveform cache; never delete imported audio.
                val files = context.cacheDir.listFiles { f -> f.name.startsWith("envelope_v") && f.extension == "bin" }
                    ?.sortedByDescending { it.lastModified() } ?: emptyList()
                var total = 0L
                files.forEach { total += it.length(); if (total > 64L * 1024 * 1024 && it != cache) it.delete() }
            } finally { temporary.delete() }
            return result
        } catch (e: Exception) {
            android.util.Log.e("Waveform", "Analysis failed: ${e.javaClass.simpleName}: ${e.message}", e)
            throw e
        } finally {
            stopped.set(true)
            // Serialize teardown after any callback already reading a buffer.
            val thread = callbackThread
            if (thread != null) {
                val released = CountDownLatch(1)
                Handler(thread.looper).post {
                    try { codec?.let { runCatching { it.stop() }; it.release() } }
                    finally { released.countDown() }
                }
                var interrupted = false
                while (true) {
                    try { released.await(); break } catch (_: InterruptedException) { interrupted = true }
                }
                thread.quitSafely()
                if (interrupted) Thread.currentThread().interrupt()
            } else codec?.let { runCatching { it.stop() }; it.release() }
            extractor.release()
        }
    }
}
