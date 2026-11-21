import 'dart:math' as math;
import 'dart:typed_data';
import 'audio_timeline.dart';

/// Immutable raw measurements. Display gain is fixed for the entire source,
/// shared by detail and overview, and retained across non-destructive edits.
class WaveformData {
  final List<double> peaks, rms;
  final int durationMs, available;
  final double gain;
  final bool cacheHit;
  final int elapsedMs;
  late final Float64List _energy = _prefix();
  late final Float64List _envelope = _prefix(mean: true);

  WaveformData(
    this.peaks,
    this.rms, {
    this.durationMs = 0,
    int? available,
    this.gain = 1,
    this.cacheHit = false,
    this.elapsedMs = 0,
  }) : available = available ?? rms.length;

  Float64List _prefix({bool mean = false}) {
    final values = Float64List(rms.length + 1);
    for (var i = 0; i < rms.length; i++) {
      values[i + 1] = values[i] + (mean ? rms[i] : rms[i] * rms[i]);
    }
    return values;
  }

  double _integral(double bin, bool mean) {
    final value = bin.clamp(0.0, rms.length.toDouble());
    final index = value.floor();
    return (mean ? _envelope : _energy)[index] +
        (index < rms.length
            ? (value - index) * rms[index] * (mean ? 1 : rms[index])
            : 0);
  }

  /// Time-weighted energy, including fractional end bins and edit joins.
  /// Unknown regions are absent, not painted as fake silent audio.
  double amplitude(
    AudioTimeline timeline,
    double startMs,
    double endMs, {
    bool overview = false,
  }) {
    if (rms.isEmpty) return double.nan;
    final sourceMs = durationMs > 0 ? durationMs : timeline.sourceDurationMs;
    var offset = 0, energy = 0.0, weight = 0.0;
    for (final span in timeline.spans) {
      if (offset >= endMs) break;
      final start = math.max(startMs, offset);
      final end = math.min(endMs, offset + span.lengthMs);
      if (end > start) {
        final a = ((span.startMs + start - offset) / sourceMs * rms.length)
            .clamp(0.0, rms.length.toDouble());
        final b = ((span.startMs + end - offset) / sourceMs * rms.length).clamp(
          a,
          rms.length.toDouble(),
        );
        if (b > available + .000001) return double.nan;
        energy += _integral(b, overview) - _integral(a, overview);
        weight += b - a;
      }
      offset += span.lengthMs;
    }
    if (weight <= 0) return double.nan;
    // The overview averages the short-time envelope. Squaring it again would
    // let brief loud syllables overshadow the pauses within a multi-second bar.
    // A fixed 1.3 display factor compensates for its much smaller drawing area.
    final level = overview
        ? math.max(0, energy) / weight * 1.3
        : math.sqrt(math.max(0, energy) / weight);
    return (level * gain).clamp(0.0, .98);
  }
}
