import 'dart:math' as math;
import 'audio_timeline.dart';
import 'edit_selection.dart';

class SaveRingtoneOptions {
  final String name;
  final bool selectionOnly;
  final int fadeInMs, fadeOutMs;
  const SaveRingtoneOptions(
    this.name,
    this.selectionOnly,
    this.fadeInMs,
    this.fadeOutMs,
  );

  AudioTimeline resolve(AudioTimeline timeline, EditSelection selection) =>
      selectionOnly
      ? timeline.extract(selection.startMs, selection.endMs)
      : timeline;
}

/// A short, actually rendered preview of an export's beginning or ending.
/// Shares the export encoder/fade processing, including short-clip limits.
class EdgePreview {
  final AudioTimeline timeline;
  final int fadeInMs, fadeOutMs;
  const EdgePreview._(this.timeline, this.fadeInMs, this.fadeOutMs);

  factory EdgePreview.of(
    AudioTimeline output, {
    required bool ending,
    required int fadeInMs,
    required int fadeOutMs,
  }) {
    const window = 3000;
    if (output.durationMs <= window) {
      return EdgePreview._(output, fadeInMs, fadeOutMs);
    }
    final limit = fadeInMs > 0 && fadeOutMs > 0
        ? output.durationMs ~/ 2
        : output.durationMs;
    final timeline = ending
        ? output.extract(output.durationMs - window, output.durationMs)
        : output.extract(0, window);
    return EdgePreview._(
      timeline,
      ending ? 0 : math.min(fadeInMs, limit),
      ending ? math.min(fadeOutMs, limit) : 0,
    );
  }
}

String selectionLength(int milliseconds) {
  final minutes = milliseconds ~/ 60000;
  final seconds = milliseconds % 60000 / 1000;
  final text = milliseconds % 1000 == 0
      ? seconds.toStringAsFixed(0)
      : seconds.toStringAsFixed(2);
  return minutes > 0 ? '$minutes 分 $text 秒' : '$text 秒';
}
