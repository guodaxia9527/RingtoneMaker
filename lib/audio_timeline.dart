import 'dart:math' as math;

/// A source interval. Edits retain references to the original audio, avoiding
/// repeated lossy encoding and preserving millisecond-accurate undo.
class AudioSpan {
  final int startMs, endMs;
  const AudioSpan(this.startMs, this.endMs);
  int get lengthMs => endMs - startMs;
  Map<String, int> toExportRange() => {
    'startUs': startMs * 1000,
    'endUs': endMs * 1000,
  };
}

class TimelineLocation {
  final int index, offsetMs;
  const TimelineLocation(this.index, this.offsetMs);
}

class AudioTimeline {
  final List<AudioSpan> spans;
  final int sourceDurationMs;
  AudioTimeline._(List<AudioSpan> spans, this.sourceDurationMs)
    : spans = List.unmodifiable(spans);
  factory AudioTimeline.full(int durationMs) {
    if (durationMs <= 0) throw ArgumentError('音频时长无效');
    return AudioTimeline._([AudioSpan(0, durationMs)], durationMs);
  }
  bool sameContent(AudioTimeline other) {
    if (sourceDurationMs != other.sourceDurationMs ||
        spans.length != other.spans.length) {
      return false;
    }
    for (var i = 0; i < spans.length; i++) {
      if (spans[i].startMs != other.spans[i].startMs ||
          spans[i].endMs != other.spans[i].endMs) {
        return false;
      }
    }
    return true;
  }

  int get durationMs => spans.fold(0, (sum, span) => sum + span.lengthMs);
  bool get isOriginal =>
      spans.length == 1 &&
      spans.first.startMs == 0 &&
      spans.first.endMs == sourceDurationMs;
  List<AudioSpan> _slice(int startMs, int endMs) {
    final result = <AudioSpan>[];
    var offset = 0;
    for (final span in spans) {
      final start = math.max(startMs, offset);
      final end = math.min(endMs, offset + span.lengthMs);
      if (end > start) {
        result.add(
          AudioSpan(span.startMs + start - offset, span.startMs + end - offset),
        );
      }
      offset += span.lengthMs;
    }
    return result;
  }

  AudioTimeline extract(int startMs, int endMs) {
    _validate(startMs, endMs);
    return AudioTimeline._(_slice(startMs, endMs), sourceDurationMs);
  }

  AudioTimeline remove(int startMs, int endMs) {
    _validate(startMs, endMs);
    final remaining = [..._slice(0, startMs), ..._slice(endMs, durationMs)];
    if (remaining.isEmpty) throw ArgumentError('不能移除整段音频');
    return AudioTimeline._(remaining, sourceDurationMs);
  }

  void _validate(int start, int end) {
    if (start < 0 || end > durationMs || end <= start) {
      throw ArgumentError('选区无效');
    }
  }

  TimelineLocation locate(int positionMs) {
    var remaining = positionMs.clamp(0, durationMs);
    for (var i = 0; i < spans.length; i++) {
      if (remaining < spans[i].lengthMs || i == spans.length - 1) {
        return TimelineLocation(i, remaining);
      }
      remaining -= spans[i].lengthMs;
    }
    return const TimelineLocation(0, 0);
  }

  int positionOf(int index, int localMs) {
    final validIndex = index.clamp(0, spans.length - 1);
    return (spans.take(validIndex).fold(0, (sum, s) => sum + s.lengthMs) +
            localMs)
        .clamp(0, durationMs);
  }

  /// Maximum original amplitude within an edited timeline interval.
  double peak(List<double> original, double startMs, double endMs) {
    if (original.isEmpty) return 0;
    var offset = 0;
    var peak = 0.0;
    for (final span in spans) {
      if (offset >= endMs) break;
      final start = math.max(startMs, offset);
      final end = math.min(endMs, offset + span.lengthMs);
      if (end > start) {
        final sourceStart = span.startMs + start - offset;
        final sourceEnd = span.startMs + end - offset;
        final first = (sourceStart / sourceDurationMs * original.length)
            .floor()
            .clamp(0, original.length - 1);
        final last = (sourceEnd / sourceDurationMs * original.length)
            .ceil()
            .clamp(first + 1, original.length);
        for (var i = first; i < last; i++) {
          peak = math.max(peak, original[i]);
        }
      }
      offset += span.lengthMs;
    }
    return peak;
  }

  double rms(List<double> original, double startMs, double endMs) {
    if (original.isEmpty) return 0;
    var offset = 0, sum = 0.0, weight = 0.0;
    for (final span in spans) {
      if (offset >= endMs) break;
      final start = math.max(startMs, offset);
      final end = math.min(endMs, offset + span.lengthMs);
      if (end > start) {
        final sourceStart = span.startMs + start - offset;
        final sourceEnd = span.startMs + end - offset;
        final first = (sourceStart / sourceDurationMs * original.length)
            .floor()
            .clamp(0, original.length - 1);
        final last = (sourceEnd / sourceDurationMs * original.length)
            .ceil()
            .clamp(first + 1, original.length);
        for (var i = first; i < last; i++) {
          sum += original[i] * original[i];
          weight++;
        }
      }
      offset += span.lengthMs;
    }
    return weight == 0 ? 0 : math.sqrt(sum / weight);
  }
}

String displayTime(int milliseconds, {bool fraction = false}) {
  final value = math.max(0, milliseconds);
  final minutes = (value ~/ 60000).toString().padLeft(2, '0');
  final seconds = (value ~/ 1000 % 60).toString().padLeft(2, '0');
  final hundredths = (value % 1000 ~/ 10).toString().padLeft(2, '0');
  return fraction ? '$minutes:$seconds.$hundredths' : '$minutes:$seconds';
}
