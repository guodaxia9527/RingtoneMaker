import 'package:flutter_test/flutter_test.dart';
import 'package:ringtone_maker/audio_timeline.dart';
import 'package:ringtone_maker/edit_selection.dart';
import 'package:ringtone_maker/export_options.dart';

void main() {
  test(
    'selected export maps across removed audio without changing the document',
    () {
      final timeline = AudioTimeline.full(60000).remove(20000, 40000);
      final selection = EditSelection.full(
        40000,
      ).withStart(15000).withEnd(25000);
      final selected = const SaveRingtoneOptions(
        'test',
        true,
        0,
        0,
      ).resolve(timeline, selection);
      expect(selected.spans.map((s) => [s.startMs, s.endMs]), [
        [15000, 20000],
        [40000, 45000],
      ]);
      expect(timeline.durationMs, 40000);
      expect(
        const SaveRingtoneOptions(
          'test',
          false,
          0,
          0,
        ).resolve(timeline, selection),
        same(timeline),
      );
    },
  );

  test('edge previews retain fade placement across edit joins', () {
    final timeline = AudioTimeline.full(10000).remove(1000, 8000);
    final short = EdgePreview.of(
      timeline,
      ending: true,
      fadeInMs: 1000,
      fadeOutMs: 500,
    );
    expect(short.timeline, same(timeline));
    expect(short.fadeInMs, 1000);
    expect(short.fadeOutMs, 500);
    final output = AudioTimeline.full(20000).remove(6000, 10000);
    final head = EdgePreview.of(
      output,
      ending: false,
      fadeInMs: 500,
      fadeOutMs: 1000,
    );
    final tail = EdgePreview.of(
      output,
      ending: true,
      fadeInMs: 500,
      fadeOutMs: 1000,
    );
    expect(head.timeline.spans.single.startMs, 0);
    expect(head.timeline.durationMs, 3000);
    expect([head.fadeInMs, head.fadeOutMs], [500, 0]);
    expect(tail.timeline.spans.single.startMs, 17000);
    expect([tail.fadeInMs, tail.fadeOutMs], [0, 1000]);
  });
}
