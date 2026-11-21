/// Positions and selections use milliseconds throughout the editor.
class EditSelection {
  final int durationMs;
  final int startMs;
  final int endMs;
  const EditSelection._(this.durationMs, this.startMs, this.endMs);
  factory EditSelection.full(int durationMs) {
    if (durationMs <= 0) throw ArgumentError('音频时长必须大于零');
    return EditSelection._(durationMs, 0, durationMs);
  }
  int get minimumMs => durationMs < 100 ? durationMs : 100;
  EditSelection withStart(int value) =>
      EditSelection._(durationMs, value.clamp(0, endMs - minimumMs), endMs);
  EditSelection withEnd(int value) => EditSelection._(
    durationMs,
    startMs,
    value.clamp(startMs + minimumMs, durationMs),
  );
  int clampPosition(int value) => value.clamp(startMs, endMs);
}

String formatTime(int milliseconds) {
  final minutes = milliseconds ~/ 60000;
  final seconds = (milliseconds ~/ 1000 % 60).toString().padLeft(2, '0');
  final millis = (milliseconds % 1000).toString().padLeft(3, '0');
  return '$minutes:$seconds.$millis';
}

int? parseTime(String text) {
  final parts = text.trim().split(':');
  if (parts.length > 2 || parts.any((p) => p.isEmpty)) return null;
  final minutes = parts.length == 2 ? int.tryParse(parts.first) : 0;
  final seconds = double.tryParse(parts.last);
  if (minutes == null ||
      minutes < 0 ||
      seconds == null ||
      !seconds.isFinite ||
      seconds < 0 ||
      (parts.length == 2 && seconds >= 60)) {
    return null;
  }
  return minutes * 60000 + (seconds * 1000).round();
}
