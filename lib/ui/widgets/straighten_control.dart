import 'package:flutter/material.dart';

class StraightenControl extends StatelessWidget {
  const StraightenControl({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  static const minDegrees = -15.0;
  static const maxDegrees = 15.0;
  static const commitThresholdDegrees = 0.01;

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  Future<void> _editExactValue(BuildContext context) async {
    if (!enabled) return;
    final result = await showDialog<double>(
      context: context,
      builder: (_) => _StraightenValueDialog(value: value),
    );
    if (result == null || !context.mounted) return;
    final normalized = result.abs() < commitThresholdDegrees ? 0.0 : result;
    onChanged(normalized);
    onChangeEnd(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(minDegrees, maxDegrees).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text('-15°'),
            Expanded(
              child: Slider(
                key: const ValueKey('straighten_slider'),
                value: clamped,
                min: minDegrees,
                max: maxDegrees,
                divisions: 60,
                label: '${clamped.toStringAsFixed(1)}°',
                onChanged: enabled ? onChanged : null,
                onChangeEnd: enabled ? onChangeEnd : null,
              ),
            ),
            const Text('15°'),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message: enabled ? 'Set exact straighten angle' : '',
            child: TextButton.icon(
              key: const ValueKey('straighten_exact_value_button'),
              onPressed: enabled ? () => _editExactValue(context) : null,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text('${clamped.toStringAsFixed(1)}°'),
            ),
          ),
        ),
      ],
    );
  }
}

class _StraightenValueDialog extends StatefulWidget {
  const _StraightenValueDialog({required this.value});

  final double value;

  @override
  State<_StraightenValueDialog> createState() => _StraightenValueDialogState();
}

class _StraightenValueDialogState extends State<_StraightenValueDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value.toStringAsFixed(1),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply() {
    final normalizedInput = _controller.text.trim().replaceAll(',', '.');
    final parsed = double.tryParse(normalizedInput);
    if (parsed == null || !parsed.isFinite) {
      setState(() => _error = 'Enter a valid angle');
      return;
    }
    Navigator.of(context).pop(
      parsed
          .clamp(StraightenControl.minDegrees, StraightenControl.maxDegrees)
          .toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set straighten angle'),
      content: TextField(
        key: const ValueKey('straighten_exact_input'),
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(
          labelText: 'Degrees',
          helperText: '-15° to 15°',
          errorText: _error,
        ),
        onSubmitted: (_) => _apply(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('straighten_exact_apply'),
          onPressed: _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
