import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../audio_timeline.dart';
import '../waveform_data.dart';

import '../app_theme.dart';
export '../app_theme.dart'
    show editorBlue, editorRed, editorGreen, editorBackground;

class DetailWaveform extends StatefulWidget {
  final AudioTimeline timeline;
  final List<double> peaks;
  final WaveformData? envelope;
  final int startMs, endMs, positionMs, windowMs;
  final int? dragOriginMs, playOriginMs, activeBoundary;
  final ValueChanged<int>? onBoundaryDragStart;
  final ValueChanged<Offset>? onPositionMenuRequested;
  final VoidCallback? onTogglePlayback;
  final bool enabled;
  final ValueChanged<int> onStart, onEnd, onSeek, onZoom;
  final VoidCallback onInteractionStart, onInteractionEnd;
  const DetailWaveform({
    super.key,
    required this.timeline,
    required this.peaks,
    this.envelope,
    required this.startMs,
    required this.endMs,
    required this.positionMs,
    required this.windowMs,
    this.dragOriginMs,
    this.playOriginMs,
    this.activeBoundary,
    this.onBoundaryDragStart,
    this.onPositionMenuRequested,
    this.onTogglePlayback,
    this.enabled = true,
    required this.onStart,
    required this.onEnd,
    required this.onSeek,
    required this.onZoom,
    required this.onInteractionStart,
    required this.onInteractionEnd,
  });
  @override
  State<DetailWaveform> createState() => _DetailWaveformState();
}

class _DetailWaveformState extends State<DetailWaveform> {
  int _mode = 2, _initialPosition = 0, _initialWindow = 0, _initialBoundary = 0;
  final _samples = _DetailSamples();
  double _initialX = 0;
  double? _downX;
  int? _downPosition, _downWindow;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      return Semantics(
        label:
            '放大波形，左右滑动定位，双指缩放，拖动蓝线调整选区'
            '${widget.enabled && widget.onTogglePlayback != null ? '，双击播放或暂停' : ''}'
            '${widget.enabled && widget.onPositionMenuRequested != null ? '，长按将当前播放位置设为起点或终点' : ''}',
        child: Listener(
          onPointerDown: (event) {
            if (_downX == null) {
              _downX = event.localPosition.dx;
              _downPosition = widget.positionMs;
              _downWindow = widget.windowMs;
            }
          },
          onPointerUp: (_) => _downX = null,
          onPointerCancel: (_) => _downX = null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: widget.enabled ? widget.onTogglePlayback : null,
            onLongPressStart:
                widget.enabled && widget.onPositionMenuRequested != null
                ? (details) =>
                      widget.onPositionMenuRequested!(details.globalPosition)
                : null,
            onScaleStart: widget.enabled
                ? (details) {
                    _initialPosition = _downPosition ?? widget.positionMs;
                    _initialWindow = _downWindow ?? widget.windowMs;
                    _initialX = _downX ?? details.localFocalPoint.dx;
                    double x(int time) =>
                        width / 2 +
                        (time - _initialPosition) / _initialWindow * width;
                    final a = (_initialX - x(widget.startMs)).abs();
                    final b = (_initialX - x(widget.endMs)).abs();
                    _mode = details.pointerCount > 1
                        ? 3
                        : math.min(a, b) <= 22
                        ? (a <= b ? 0 : 1)
                        : 2;
                    _initialBoundary = _mode == 0
                        ? widget.startMs
                        : widget.endMs;
                    if ((_mode == 0 || _mode == 1) &&
                        widget.onBoundaryDragStart != null) {
                      widget.onBoundaryDragStart!(_mode);
                    } else {
                      widget.onInteractionStart();
                    }
                  }
                : null,
            onScaleUpdate: widget.enabled
                ? (details) {
                    if (details.pointerCount > 1 ||
                        (details.scale - 1).abs() > .03) {
                      _mode = 3;
                    }
                    final deltaMs =
                        (details.localFocalPoint.dx - _initialX) /
                        width *
                        _initialWindow;
                    if (_mode == 3) {
                      widget.onZoom((_initialWindow / details.scale).round());
                    } else if (_mode == 0) {
                      widget.onStart((_initialBoundary + deltaMs).round());
                    } else if (_mode == 1) {
                      widget.onEnd((_initialBoundary + deltaMs).round());
                    } else {
                      widget.onSeek((_initialPosition - deltaMs).round());
                    }
                  }
                : null,
            onScaleEnd: widget.enabled
                ? (_) => widget.onInteractionEnd()
                : null,
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                willChange: true,
                painter: _DetailPainter(widget, _samples),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _DetailSamples {
  AudioTimeline? _timeline;
  List<double>? _peaks;
  WaveformData? _envelope;
  int? _windowMs;
  double? _width;
  int _first = 0;
  List<double> _values = [];

  void prepare(DetailWaveform wave, Size size) {
    final stepMs = wave.windowMs / size.width * 3.5;
    final visibleFirst = ((wave.positionMs - wave.windowMs / 2) / stepMs)
        .floor();
    final count = (size.width / 3.5).ceil() + 3;
    if (identical(_timeline, wave.timeline) &&
        identical(_peaks, wave.peaks) &&
        identical(_envelope, wave.envelope) &&
        _windowMs == wave.windowMs &&
        _width == size.width &&
        visibleFirst >= _first &&
        visibleFirst + count < _first + _values.length) {
      return;
    }
    _timeline = wave.timeline;
    _peaks = wave.peaks;
    _envelope = wave.envelope;
    _windowMs = wave.windowMs;
    _width = size.width;
    _first = visibleFirst - count ~/ 2;
    _values = List.generate(count * 2, (i) {
      final start = (_first + i) * stepMs;
      if (wave.peaks.isEmpty) return double.nan;
      return wave.envelope?.amplitude(wave.timeline, start, start + stepMs) ??
          wave.timeline.rms(wave.peaks, start, start + stepMs);
    });
  }

  double at(int bucket) => _values[bucket - _first];
}

class _DetailPainter extends CustomPainter {
  final DetailWaveform wave;
  final _DetailSamples samples;
  _DetailPainter(this.wave, this.samples);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = editorBackground);
    final windowStart = wave.positionMs - wave.windowMs / 2;
    double x(num time) =>
        size.width / 2 + (time - wave.positionMs) / wave.windowMs * size.width;
    const top = 32.0;
    final bottom = size.height - 6;
    final centerY = (top + bottom) / 2;
    final left = x(wave.startMs).clamp(0.0, size.width);
    final right = x(wave.endMs).clamp(0.0, size.width);
    canvas.drawRect(
      Rect.fromLTRB(left, top, right, bottom),
      Paint()..color = editorBlue.withValues(alpha: .14),
    );
    final interval = [100, 200, 500, 1000, 2000, 5000, 10000, 30000, 60000]
        .firstWhere(
          (i) => i >= wave.windowMs / size.width * 86,
          orElse: () => 60000,
        );
    final minor = interval / 4;
    for (
      var time = (windowStart / minor).floor() * minor;
      time <= windowStart + wave.windowMs;
      time += minor
    ) {
      if (time < 0 || time > wave.timeline.durationMs) continue;
      final px = x(time);
      final major = (time / interval - (time / interval).round()).abs() < .001;
      canvas.drawLine(
        Offset(px, major ? 23 : 27),
        Offset(px, top),
        Paint()..color = const Color(0xFFB3B5B9),
      );
      if (major) {
        final label = TextPainter(
          text: TextSpan(
            text: displayTime(time.round(), fraction: interval < 1000),
            style: const TextStyle(
              color: Color(0xFF74777A),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        // Let the label move out of the viewport naturally. Clamping its
        // anchor to x=0 made it appear stuck at the edge during playback.
        label.paint(canvas, Offset(px - label.width / 2, 5));
      }
    }
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, top, size.width, bottom));
    final paint = Paint()
      ..color = const Color(0xFF101A24)
      ..strokeWidth = 1.35
      ..strokeCap = StrokeCap.round;
    samples.prepare(wave, size);
    final sampleMs = wave.windowMs / size.width * 3.5;
    final first = (windowStart / sampleMs).floor();
    final last = ((windowStart + wave.windowMs) / sampleMs).ceil();
    for (var bucket = first; bucket <= last; bucket++) {
      final a = bucket * sampleMs, b = (bucket + 1) * sampleMs;
      if (b <= 0 || a >= wave.timeline.durationMs) continue;
      final px = x(a);
      final amplitude = samples.at(bucket);
      if (!amplitude.isFinite) continue;
      final h = math.max(1.2, amplitude * (bottom - top) * .45);
      canvas.drawLine(Offset(px, centerY - h), Offset(px, centerY + h), paint);
    }
    for (final origin in {wave.playOriginMs, wave.dragOriginMs}) {
      if (origin == null) continue;
      final px = x(origin);
      if (px < 0 || px > size.width) continue;
      for (double y = top; y < bottom; y += 7) {
        canvas.drawLine(
          Offset(px, y),
          Offset(px, math.min(y + 3.5, bottom)),
          Paint()
            ..color = const Color(0xFF92969A)
            ..strokeWidth = 1,
        );
      }
    }
    for (var i = 0; i < 2; i++) {
      final boundary = i == 0 ? wave.startMs : wave.endMs;
      final color = wave.activeBoundary == i ? editorRed : editorBlue;
      final px = x(boundary);
      if (px < 0 || px > size.width) continue;
      canvas.drawLine(
        Offset(px, top),
        Offset(px, bottom),
        Paint()
          ..color = color
          ..strokeWidth = 1.5,
      );
      canvas.drawCircle(Offset(px, centerY), 4, Paint()..color = color);
    }
    canvas.drawLine(
      Offset(size.width / 2, top),
      Offset(size.width / 2, bottom),
      Paint()
        ..color = editorGreen
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DetailPainter old) => true;
}

class OverviewWaveform extends StatefulWidget {
  final AudioTimeline timeline;
  final List<double> peaks;
  final WaveformData? envelope;
  final int startMs, endMs, positionMs;
  final int? referenceMs;
  final bool playing;
  final bool enabled;
  final ValueChanged<int> onStart, onEnd;
  final VoidCallback onInteractionStart, onInteractionEnd;
  const OverviewWaveform({
    super.key,
    required this.timeline,
    required this.peaks,
    this.envelope,
    required this.startMs,
    required this.endMs,
    required this.positionMs,
    this.referenceMs,
    this.playing = false,
    required this.onStart,
    required this.onEnd,
    required this.onInteractionStart,
    required this.onInteractionEnd,
    this.enabled = true,
  });
  @override
  State<OverviewWaveform> createState() => _OverviewWaveformState();
}

// Boundary times sit at the inner edges of the grips. All waveform painting,
// playhead positioning and hit testing share this same time axis.
class _OverviewGeometry {
  static const handleWidth = 23.0;
  static const inset = handleWidth + 2;
  final double width;
  final int durationMs;
  const _OverviewGeometry(this.width, this.durationMs);

  double get trackWidth => math.max(1, width - inset * 2);
  double x(num time) => inset + time / durationMs * trackWidth;
  int time(double px) => ((px - inset) / trackWidth * durationMs).round();
  double handleCenter(int time, bool start) =>
      x(time) + (start ? -handleWidth / 2 : handleWidth / 2);
}

class _OverviewWaveformState extends State<OverviewWaveform> {
  int? _handle;
  int? _dragReference;
  bool _snapped = false;
  double _grabOffset = 0;
  AudioTimeline? _cachedTimeline;
  List<double>? _cachedPeaks;
  WaveformData? _cachedEnvelope;
  double? _cachedWidth;
  List<double> _bars = [];

  int _dragTime(double px, _OverviewGeometry geometry) {
    final reference = _dragReference;
    final minimum = math.min(100, widget.timeline.durationMs);
    final canSnap =
        reference != null &&
        reference >= 0 &&
        reference <= widget.timeline.durationMs &&
        (_handle == 0
            ? reference <= widget.endMs - minimum
            : reference >= widget.startMs + minimum);
    if (canSnap) {
      final distance = (px - geometry.x(reference)).abs();
      // A wider release radius keeps small finger movements from repeatedly
      // snapping/unsnapping and buzzing around the reference.
      if (distance <= (_snapped ? 11 : 6)) {
        if (!_snapped) {
          unawaited(HapticFeedback.selectionClick().catchError((Object _) {}));
        }
        _snapped = true;
        return reference;
      }
    }
    _snapped = false;
    return geometry.time(px);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final geometry = _OverviewGeometry(width, widget.timeline.durationMs);
      if (!identical(_cachedTimeline, widget.timeline) ||
          !identical(_cachedPeaks, widget.peaks) ||
          !identical(_cachedEnvelope, widget.envelope) ||
          _cachedWidth != width) {
        _cachedTimeline = widget.timeline;
        _cachedPeaks = widget.peaks;
        _cachedEnvelope = widget.envelope;
        _cachedWidth = width;
        final count = (geometry.trackWidth / 1.6).ceil();
        _bars = List.generate(count, (i) {
          final start = i / count * widget.timeline.durationMs;
          final end = (i + 1) / count * widget.timeline.durationMs;
          if (widget.peaks.isEmpty) return double.nan;
          return widget.envelope?.amplitude(
                widget.timeline,
                start,
                end,
                overview: true,
              ) ??
              widget.timeline.rms(widget.peaks, start, end);
        });
      }
      return Semantics(
        label: '完整波形，只能拖动蓝色框的左右手柄调整选区，暂停后拖动可吸附到原播放位置',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: widget.enabled
              ? (details) {
                  final a =
                      (details.localPosition.dx -
                              geometry.handleCenter(widget.startMs, true))
                          .abs();
                  final b =
                      (details.localPosition.dx -
                              geometry.handleCenter(widget.endMs, false))
                          .abs();
                  _handle = math.min(a, b) <= 24 ? (a <= b ? 0 : 1) : null;
                  if (_handle != null) {
                    _dragReference =
                        widget.referenceMs ??
                        (widget.playing ? null : widget.positionMs);
                    _snapped = false;
                    _grabOffset =
                        details.localPosition.dx -
                        geometry.x(
                          _handle == 0 ? widget.startMs : widget.endMs,
                        );
                    widget.onInteractionStart();
                  }
                }
              : null,
          onHorizontalDragUpdate: widget.enabled
              ? (details) {
                  if (_handle == 0) {
                    widget.onStart(
                      _dragTime(
                        details.localPosition.dx - _grabOffset,
                        geometry,
                      ),
                    );
                  }
                  if (_handle == 1) {
                    widget.onEnd(
                      _dragTime(
                        details.localPosition.dx - _grabOffset,
                        geometry,
                      ),
                    );
                  }
                }
              : null,
          onHorizontalDragEnd: (_) {
            if (_handle != null) widget.onInteractionEnd();
            _handle = null;
            _dragReference = null;
            _snapped = false;
          },
          onHorizontalDragCancel: () {
            if (_handle != null) widget.onInteractionEnd();
            _handle = null;
            _dragReference = null;
            _snapped = false;
          },
          child: SizedBox(
            height: 66,
            width: double.infinity,
            child: CustomPaint(painter: _OverviewPainter(widget, _bars)),
          ),
        ),
      );
    },
  );
}

class _OverviewPainter extends CustomPainter {
  final OverviewWaveform wave;
  final List<double> bars;
  _OverviewPainter(this.wave, this.bars);
  @override
  void paint(Canvas canvas, Size size) {
    final geometry = _OverviewGeometry(size.width, wave.timeline.durationMs);
    double x(int time) => geometry.x(time);
    final left = x(wave.startMs), right = x(wave.endMs);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 5, size.width, 56),
        const Radius.circular(10),
      ),
      Paint()..color = const Color(0xFFE3E5E8),
    );
    canvas.drawRect(
      Rect.fromLTRB(left, 7, right, 59),
      Paint()..color = editorBlue.withValues(alpha: .14),
    );
    final paint = Paint()
      ..color = const Color(0xFF293847)
      ..strokeWidth = .7
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < bars.length; i++) {
      if (!bars[i].isFinite) continue;
      final px = geometry.x((i + .5) / bars.length * wave.timeline.durationMs);
      final h = math.max(.7, bars[i] * 23.4);
      canvas.drawLine(Offset(px, 33 - h), Offset(px, 33 + h), paint);
    }
    final selection = Rect.fromLTRB(
      left - _OverviewGeometry.handleWidth,
      5,
      right + _OverviewGeometry.handleWidth,
      61,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(selection, const Radius.circular(10)),
      Paint()
        ..color = editorBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    final leftCap = Rect.fromLTRB(
      selection.left,
      selection.top,
      left,
      selection.bottom,
    );
    final rightCap = Rect.fromLTRB(
      right,
      selection.top,
      selection.right,
      selection.bottom,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        leftCap,
        topLeft: const Radius.circular(10),
        bottomLeft: const Radius.circular(10),
      ),
      Paint()..color = editorBlue,
    );
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        rightCap,
        topRight: const Radius.circular(10),
        bottomRight: const Radius.circular(10),
      ),
      Paint()..color = editorBlue,
    );
    for (final px in [leftCap.center.dx, rightCap.center.dx]) {
      canvas.drawLine(
        Offset(px, 25),
        Offset(px, 41),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
    final reference = wave.referenceMs;
    if (reference != null &&
        reference >= 0 &&
        reference <= wave.timeline.durationMs) {
      final px = x(reference);
      const color = Color(0xFF5F6B76);
      // Draw above grips as well, so the target stays legible when a grip
      // passes over it. The top notch remains visible when the green head
      // and this reference coincide after snapping.
      canvas.drawPath(
        Path()
          ..moveTo(px - 3.5, 0)
          ..lineTo(px + 3.5, 0)
          ..lineTo(px, 5)
          ..close(),
        Paint()..color = color,
      );
      for (double y = 8; y < 59; y += 8) {
        final end = math.min(y + 4, 59.0);
        canvas.drawLine(
          Offset(px, y),
          Offset(px, end),
          Paint()
            ..color = Colors.white
            ..strokeWidth = 3.5,
        );
        canvas.drawLine(
          Offset(px, y),
          Offset(px, end),
          Paint()
            ..color = color
            ..strokeWidth = 1.5,
        );
      }
    }
    final head = x(wave.positionMs);
    canvas.drawRect(
      Rect.fromLTRB(head - 1, 7, head + 1, 59),
      Paint()..color = editorGreen,
    );
  }

  @override
  bool shouldRepaint(covariant _OverviewPainter old) => true;
}
