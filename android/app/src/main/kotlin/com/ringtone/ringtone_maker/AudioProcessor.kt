package com.ringtone.ringtone_maker

import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.SystemClock
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.min

/**
 * Decodes bounded PCM buffers. Waveform memory is independent of input length.
 * Export spools only the selected PCM to cache before AAC encoding.
 */
object AudioProcessor {
    private fun check(cancelled: () -> Boolean) {
        if (Thread.currentThread().isInterrupted || cancelled()) throw InterruptedException("操作已取消")
    }

    private fun decode(
        path: String, startUs: Long, endUs: Long, cancelled: () -> Boolean, context: Context?,
        onFormat: (Int, Int) -> Unit,
        onPcm: (ByteArray, Long, Int, Int) -> Unit
    ) {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        try {
            if (context != null) AudioSourceAccess.open(extractor, context, path) else extractor.setDataSource(path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: error("文件没有可解码音轨")
            extractor.selectTrack(track)
            val input = extractor.getTrackFormat(track)
            extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            val decoder = MediaCodec.createDecoderByType(input.getString(MediaFormat.KEY_MIME)!!)
            codec = decoder
            decoder.configure(input, null, null, 0)
            decoder.start()
            var rate = input.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = input.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var encoding = AudioFormat.ENCODING_PCM_16BIT
            var inputDone = false
            var outputDone = false
            var lastActivity = SystemClock.elapsedRealtime()
            val info = MediaCodec.BufferInfo()
            onFormat(rate, channels)
            while (!outputDone) {
                check(cancelled)
                if (SystemClock.elapsedRealtime() - lastActivity > 30000) error("音频解码超时")
                if (!inputDone) {
                    val index = decoder.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val time = extractor.sampleTime
                        val buffer = decoder.getInputBuffer(index)!!
                        buffer.clear()
                        // Negative timestamps can be valid AAC preroll packets.
                        // readSampleData reports EOS; output trimming below removes preroll.
                        val size = if (time >= endUs) -1 else extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(index, 0, size, time, 0)
                            extractor.advance()
                        }
                        lastActivity = SystemClock.elapsedRealtime()
                    }
                }
                when (val index = decoder.dequeueOutputBuffer(info, 10000)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val format = decoder.outputFormat
                        rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        encoding = if (format.containsKey(MediaFormat.KEY_PCM_ENCODING))
                            format.getInteger(MediaFormat.KEY_PCM_ENCODING) else AudioFormat.ENCODING_PCM_16BIT
                        onFormat(rate, channels)
                        lastActivity = SystemClock.elapsedRealtime()
                    }
                    else -> if (index >= 0) {
                        try {
                            if (info.size > 0) {
                                val bytesPerSample = when (encoding) {
                                    AudioFormat.ENCODING_PCM_8BIT -> 1
                                    AudioFormat.ENCODING_PCM_16BIT -> 2
                                    AudioFormat.ENCODING_PCM_FLOAT, AudioFormat.ENCODING_PCM_32BIT -> 4
                                    AudioFormat.ENCODING_PCM_24BIT_PACKED -> 3
                                    else -> error("不支持的 PCM 编码：$encoding")
                                }
                                val frameBytes = channels * bytesPerSample
                                val frames = info.size / frameBytes
                                val first = ceil((startUs - info.presentationTimeUs).toDouble() * rate / 1000000)
                                    .toInt().coerceIn(0, frames)
                                val last = ceil((endUs - info.presentationTimeUs).toDouble() * rate / 1000000)
                                    .toInt().coerceIn(first, frames)
                                if (last > first) {
                                    val buffer = decoder.getOutputBuffer(index)!!.order(ByteOrder.LITTLE_ENDIAN)
                                    buffer.position(info.offset + first * frameBytes)
                                    buffer.limit(info.offset + last * frameBytes)
                                    // Normalize platform PCM formats to signed little endian 16 bit.
                                    val pcm = ByteArray((last - first) * channels * 2)
                                    val output = ByteBuffer.wrap(pcm).order(ByteOrder.LITTLE_ENDIAN)
                                    while (buffer.remaining() >= bytesPerSample) {
                                        val sample = when (encoding) {
                                            AudioFormat.ENCODING_PCM_8BIT -> ((buffer.get().toInt() and 255) - 128) shl 8
                                            AudioFormat.ENCODING_PCM_16BIT -> buffer.short.toInt()
                                            AudioFormat.ENCODING_PCM_FLOAT -> (buffer.float.coerceIn(-1f, 1f) * 32767).toInt()
                                            AudioFormat.ENCODING_PCM_32BIT -> buffer.int shr 16
                                            else -> {
                                                buffer.get()
                                                val mid = buffer.get().toInt() and 255
                                                val high = buffer.get().toInt()
                                                (high shl 8) or mid
                                            }
                                        }
                                        output.putShort(sample.coerceIn(-32768, 32767).toShort())
                                    }
                                    val time = info.presentationTimeUs + first.toLong() * 1000000 / rate
                                    onPcm(pcm, time, rate, channels)
                                }
                            }
                            outputDone = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        } finally {
                            decoder.releaseOutputBuffer(index, false)
                        }
                        lastActivity = SystemClock.elapsedRealtime()
                    }
                }
            }
        } finally {
            codec?.let { runCatching { it.stop() }; it.release() }
            extractor.release()
        }
    }

    fun export(path: String, output: File, cacheDir: File, ranges: List<Pair<Long, Long>>, fadeInMs: Int = 0, fadeOutMs: Int = 0, context: Context? = null) {
        require(fadeInMs in 0..5000 && fadeOutMs in 0..5000)
        require(ranges.isNotEmpty() && ranges.all { it.first >= 0 && it.second > it.first }) { "选区无效" }
        val pcm = File.createTempFile("selection_", ".pcm", cacheDir)
        var sampleRate = 0
        var channelCount = 0
        var pcmWritten = 0L
        try {
            pcm.outputStream().buffered().use { stream ->
                for ((startUs, endUs) in ranges) {
                decode(path, startUs, endUs, { false }, context, { rate, channels ->
                    if (sampleRate != 0 && (rate != sampleRate || channels != channelCount) && pcmWritten > 0)
                        error("音轨中途改变采样格式")
                    sampleRate = rate
                    channelCount = channels
                }) { bytes, _, _, _ -> stream.write(bytes); pcmWritten += bytes.size }
                }
            }
            require(pcm.length() > 0) { "选区内没有音频" }
            applyFades(pcm, sampleRate, channelCount, fadeInMs, fadeOutMs)
            encode(pcm, output, sampleRate, channelCount)
        } catch (e: Exception) {
            output.delete()
            throw e
        } finally { pcm.delete() }
    }

    private fun applyFades(pcm: File, rate: Int, channels: Int, fadeInMs: Int, fadeOutMs: Int) {
        val frameBytes = channels * 2
        val frames = pcm.length() / frameBytes
        val limit = if (fadeInMs > 0 && fadeOutMs > 0) frames / 2 else frames
        java.io.RandomAccessFile(pcm, "rw").use { file ->
            fun ramp(milliseconds: Int, rising: Boolean) {
                val count = min(rate.toLong() * milliseconds / 1000, limit)
                if (count < 2) return
                val start = if (rising) 0L else frames - count
                val buffer = ByteArray(max(frameBytes, 16384 / frameBytes * frameBytes))
                var done = 0L
                while (done < count) {
                    val chunkFrames = min((buffer.size / frameBytes).toLong(), count - done).toInt()
                    val size = chunkFrames * frameBytes
                    val offset = (start + done) * frameBytes
                    file.seek(offset)
                    file.readFully(buffer, 0, size)
                    val samples = ByteBuffer.wrap(buffer, 0, size).order(ByteOrder.LITTLE_ENDIAN)
                    for (frame in 0 until chunkFrames) {
                        val fraction = (done + frame).toDouble() / (count - 1)
                        val gain = if (rising) fraction else 1.0 - fraction
                        repeat(channels) {
                            val index = samples.position()
                            val value = samples.short
                            samples.putShort(index, (value * gain).toInt().toShort())
                        }
                    }
                    file.seek(offset)
                    file.write(buffer, 0, size)
                    done += chunkFrames
                }
            }
            ramp(fadeInMs, true)
            ramp(fadeOutMs, false)
        }
    }

    private fun encode(pcm: File, output: File, rate: Int, channels: Int) {
        var codec: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var muxerStarted = false
        try {
            val format = MediaFormat.createAudioFormat("audio/mp4a-latm", rate, channels).apply {
                setInteger(MediaFormat.KEY_BIT_RATE, 128000)
                setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            }
            val encoder = MediaCodec.createEncoderByType("audio/mp4a-latm")
            codec = encoder
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoder.start()
            val mux = MediaMuxer(output.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer = mux
            var track = -1
            var inputDone = false
            var outputDone = false
            var frames = 0L
            var lastActivity = SystemClock.elapsedRealtime()
            val info = MediaCodec.BufferInfo()
            pcm.inputStream().buffered().use { stream ->
                while (!outputDone) {
                    check { false }
                    if (SystemClock.elapsedRealtime() - lastActivity > 30000) error("音频编码超时")
                    if (!inputDone) {
                        val index = encoder.dequeueInputBuffer(10000)
                        if (index >= 0) {
                            val buffer = encoder.getInputBuffer(index)!!
                            buffer.clear()
                            val length = min(buffer.remaining(), 16384) / (channels * 2) * channels * 2
                            require(length > 0)
                            val bytes = ByteArray(length)
                            var count = 0
                            while (count < length) {
                                val read = stream.read(bytes, count, length - count)
                                if (read < 0) break
                                count += read
                            }
                            val pts = frames * 1000000 / rate
                            if (count == 0) {
                                encoder.queueInputBuffer(index, 0, 0, pts, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                buffer.put(bytes, 0, count)
                                encoder.queueInputBuffer(index, 0, count, pts, 0)
                                frames += count / (channels * 2)
                            }
                            lastActivity = SystemClock.elapsedRealtime()
                        }
                    }
                    when (val index = encoder.dequeueOutputBuffer(info, 10000)) {
                        MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            track = mux.addTrack(encoder.outputFormat)
                            mux.start()
                            muxerStarted = true
                            lastActivity = SystemClock.elapsedRealtime()
                        }
                        else -> if (index >= 0) {
                            try {
                                if (info.size > 0 && info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                                    check(muxerStarted)
                                    val buffer = encoder.getOutputBuffer(index)!!
                                    buffer.position(info.offset)
                                    buffer.limit(info.offset + info.size)
                                    mux.writeSampleData(track, buffer, info)
                                }
                                outputDone = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            } finally { encoder.releaseOutputBuffer(index, false) }
                            lastActivity = SystemClock.elapsedRealtime()
                        }
                    }
                }
            }
            require(muxerStarted) { "编码器未生成音频" }
            mux.stop()
            muxerStarted = false
        } finally {
            codec?.let { runCatching { it.stop() }; it.release() }
            if (muxerStarted) runCatching { muxer?.stop() }
            muxer?.release()
        }
    }
}
