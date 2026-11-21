import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:ringtone_maker/audio_timeline.dart';
import 'package:ringtone_maker/waveform_data.dart';

void main() {
  test(
    'overview energy preserves quiet passages instead of spreading peaks',
    () {
      final rms = List<double>.filled(100, .05)..[50] = .9;
      final data = WaveformData(rms, rms, durationMs: 2000);
      final timeline = AudioTimeline.full(2000);
      expect(data.amplitude(timeline, 0, 2000), lessThan(.11));
      expect(data.amplitude(timeline, 1000, 1020), closeTo(.9, 1e-8));
      expect(data.amplitude(timeline, 0, 1000), closeTo(.05, 1e-8));
      expect(
        data.amplitude(timeline, 0, 2000, overview: true),
        closeTo(.0585 * 1.3, 1e-8),
      );
    },
  );

  test(
    'partial bins and joins are weighted by their actual retained duration',
    () {
      final data = WaveformData([.2, .8], [.2, .8], durationMs: 2000);
      final original = AudioTimeline.full(2000);
      expect(
        data.amplitude(original, 500, 1250),
        closeTo(math.sqrt(.24), 1e-8),
      );
      final edited = original.remove(500, 1750);
      expect(data.amplitude(edited, 0, 750), closeTo(math.sqrt(.24), 1e-8));
      expect(data.amplitude(edited.extract(0, 500), 0, 500), closeTo(.2, 1e-8));
    },
  );

  test('unprocessed audio is distinct from silence and never shifts gain', () {
    final data = WaveformData(
      [.2, 0, 0],
      [.2, 0, 0],
      durationMs: 3000,
      available: 2,
      gain: 2,
    );
    final timeline = AudioTimeline.full(3000);
    expect(data.amplitude(timeline, 0, 1000), closeTo(.4, 1e-8));
    expect(data.amplitude(timeline, 1000, 2000), 0);
    expect(data.amplitude(timeline, 1900, 2100).isNaN, isTrue);
    expect(
      data.amplitude(timeline.extract(0, 1000), 0, 1000),
      closeTo(.4, 1e-8),
    );
  });
}
