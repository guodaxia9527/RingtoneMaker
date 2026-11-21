import 'package:flutter/material.dart';
import '../edit_selection.dart';

class BoundaryDialog extends StatefulWidget {
  final bool start;
  final EditSelection selection;
  final int positionMs;
  const BoundaryDialog({
    super.key,
    required this.start,
    required this.selection,
    required this.positionMs,
  });
  @override
  State<BoundaryDialog> createState() => _BoundaryDialogState();
}

class _BoundaryDialogState extends State<BoundaryDialog> {
  late final _controller = TextEditingController(
    text: formatTime(
      widget.start ? widget.selection.startMs : widget.selection.endMs,
    ),
  );
  String? _error;
  int get _minimum =>
      widget.start ? 0 : widget.selection.startMs + widget.selection.minimumMs;
  int get _maximum => widget.start
      ? widget.selection.endMs - widget.selection.minimumMs
      : widget.selection.durationMs;

  void _set(int value) => setState(() {
    _controller.text = formatTime(value.clamp(_minimum, _maximum));
    _error = null;
  });

  void _confirm() {
    final value = parseTime(_controller.text);
    if (value == null || value < _minimum || value > _maximum) {
      setState(
        () => _error = '请输入 ${formatTime(_minimum)} 至 ${formatTime(_maximum)}',
      );
    } else {
      Navigator.pop(context, value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.start ? '调整起点' : '调整终点'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('boundary-time'),
            controller: _controller,
            keyboardType: TextInputType.datetime,
            onSubmitted: (_) => _confirm(),
            decoration: InputDecoration(
              labelText: '时间',
              hintText: '分:秒.毫秒',
              helperText: '也可直接输入秒数，例如 12.5',
              errorText: _error,
              errorMaxLines: 2,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: () =>
                    _set((parseTime(_controller.text) ?? _minimum) - 50),
                child: const Text('− 0.05 秒'),
              ),
              OutlinedButton(
                onPressed: () =>
                    _set((parseTime(_controller.text) ?? _minimum) + 50),
                child: const Text('+ 0.05 秒'),
              ),
            ],
          ),
          TextButton(
            onPressed:
                widget.positionMs >= _minimum && widget.positionMs <= _maximum
                ? () => _set(widget.positionMs)
                : null,
            child: const Text('设为当前播放位置'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _confirm, child: const Text('确定')),
    ],
  );
}
