import 'package:flutter_test/flutter_test.dart';
import 'package:ringtone_maker/audio_timeline.dart';

void main() {
  test('remove joins source intervals and maps playback at the join', () {
    final edited = AudioTimeline.full(10000).remove(2000, 4000);
    expect(edited.durationMs, 8000);
    expect(edited.spans.map((s) => [s.startMs, s.endMs]), [
      [0, 2000],
      [4000, 10000],
    ]);
    expect(edited.locate(2000).index, 1);
    expect(edited.locate(2000).offsetMs, 0);
    expect(edited.positionOf(1, 1000), 3000);
  });
  test('repeated extract and remove retain original sample references', () {
    final edited = AudioTimeline.full(
      10000,
    ).remove(2000, 4000).extract(1000, 5000).remove(500, 1500);
    expect(edited.durationMs, 3000);
    expect(edited.spans.map((s) => [s.startMs, s.endMs]), [
      [1000, 1500],
      [4500, 7000],
    ]);
    expect(edited.spans.last.toExportRange(), {
      'startUs': 4500000,
      'endUs': 7000000,
    });
    expect(edited.locate(3000).offsetMs, 2500);
  });
  test('removed amplitudes do not appear in edited waveform', () {
    final edited = AudioTimeline.full(6000).remove(2000, 4000);
    final peaks = [.2, .2, 1.0, 1.0, .5, .5];
    expect(edited.peak(peaks, 0, 4000), .5);
    expect(edited.peak(peaks, 1900, 2100), .5);
    expect(edited.peak(peaks, -1000, 500), .2);
  });
  test('empty or invalid edits cannot destroy the document', () {
    final doc = AudioTimeline.full(1000);
    expect(() => doc.remove(0, 1000), throwsArgumentError);
    expect(() => doc.extract(500, 500), throwsArgumentError);
    expect(() => doc.extract(-1, 500), throwsArgumentError);
    expect(doc.durationMs, 1000);
  });
  test(
    'saved content comparison checks source intervals, not only duration',
    () {
      final doc = AudioTimeline.full(6000);
      expect(doc.sameContent(AudioTimeline.full(6000)), isTrue);
      expect(doc.sameContent(doc.extract(0, 6000)), isTrue);
      expect(
        doc.extract(0, 2000).sameContent(doc.extract(4000, 6000)),
        isFalse,
      );
      expect(doc.remove(2000, 4000).sameContent(doc.extract(0, 4000)), isFalse);
    },
  );
}
