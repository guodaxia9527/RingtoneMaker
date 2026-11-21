import 'package:flutter/material.dart';

/// Leading ellipsis preserves the identifying suffix without reversing bidi text.
class TailFilename extends StatefulWidget {
  final String name;
  final TextStyle style;
  final TextAlign textAlign;
  const TailFilename({
    super.key,
    required this.name,
    required this.style,
    this.textAlign = TextAlign.center,
  });
  @override
  State<TailFilename> createState() => _TailFilenameState();
}

class _TailFilenameState extends State<TailFilename> {
  String? _name, _display;
  double? _width;
  TextStyle? _style;
  TextScaler? _scaler;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = DefaultTextStyle.of(context).style.merge(widget.style);
      final scaler = MediaQuery.textScalerOf(context);
      if (_name != widget.name ||
          _width != constraints.maxWidth ||
          _style != style ||
          _scaler != scaler) {
        _name = widget.name;
        _width = constraints.maxWidth;
        _style = style;
        _scaler = scaler;
        final painter = TextPainter(
          textDirection: TextDirection.ltr,
          textScaler: scaler,
          maxLines: 1,
        );
        bool fits(String value) {
          painter.text = TextSpan(text: value, style: style);
          painter.layout();
          return painter.width <= constraints.maxWidth;
        }

        if (fits(widget.name)) {
          _display = widget.name;
        } else {
          final characters = widget.name.characters.toList(growable: false);
          var low = 0, high = characters.length;
          while (low < high) {
            final middle = (low + high) ~/ 2;
            if (fits('…${characters.skip(middle).join()}')) {
              high = middle;
            } else {
              low = middle + 1;
            }
          }
          _display = '…${characters.skip(low).join()}';
        }
        painter.dispose();
      }
      return Tooltip(
        message: widget.name,
        child: Semantics(
          label: widget.name,
          child: ExcludeSemantics(
            child: Text(
              _display!,
              maxLines: 1,
              overflow: TextOverflow.clip,
              textDirection: TextDirection.ltr,
              textAlign: widget.textAlign,
              style: widget.style,
            ),
          ),
        ),
      );
    },
  );
}
