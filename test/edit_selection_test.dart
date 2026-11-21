import 'package:flutter_test/flutter_test.dart';
import 'package:ringtone_maker/edit_selection.dart';

void main() {
  test('dragged endpoints cannot cross or exceed audio bounds', () {
    var selection = EditSelection.full(60000).withStart(10000).withEnd(20000);
    expect(selection.withStart(30000).startMs, 19900);
    expect(selection.withStart(-100).startMs, 0);
    expect(selection.withEnd(0).endMs, 10100);
    expect(selection.withEnd(80000).endMs, 60000);
    expect(selection.clampPosition(0), 10000);
    expect(selection.clampPosition(60000), 20000);
  });
  test('subsecond input stays within actual duration', () {
    final short = EditSelection.full(40);
    expect(short.withStart(500).startMs, 0);
    expect(short.withEnd(-1).endMs, 40);
    expect(() => EditSelection.full(0), throwsArgumentError);
  });
  test('time input round trips long files without wrapping minutes', () {
    for (final time in [0, 123, 59999, 60000, 3600123, 86400123]) {
      expect(parseTime(formatTime(time)), time);
    }
    expect(parseTime('12.345'), 12345);
    expect(parseTime('2:03.456'), 123456);
    for (final invalid in ['', '-1', 'NaN', 'Infinity', '1:60', '1::2', 'x']) {
      expect(parseTime(invalid), isNull, reason: invalid);
    }
  });
}
