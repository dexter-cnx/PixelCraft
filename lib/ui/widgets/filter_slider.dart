import 'package:flutter/material.dart';

class FilterSlider extends StatefulWidget {
  const FilterSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChangeEnd,
    this.onChangeStart,
    this.onChanged,
    this.enabled = true,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChangeEnd;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChanged;
  final bool enabled;

  @override
  State<FilterSlider> createState() => _FilterSliderState();
}

class _FilterSliderState extends State<FilterSlider> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(covariant FilterSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value ||
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max) {
      _value = widget.value.clamp(widget.min, widget.max).toDouble();
    }
  }

  Future<void> _editExactValue() async {
    if (!widget.enabled) return;

    final result = await showDialog<double>(
      context: context,
      builder: (_) => _ExactValueDialog(
        value: _value,
        min: widget.min,
        max: widget.max,
      ),
    );

    if (result == null || !mounted) return;
    setState(() => _value = result);
    widget.onChangeEnd(result);
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Slider(
              value: _value.clamp(widget.min, widget.max).toDouble(),
              min: widget.min,
              max: widget.max,
              divisions: 100,
              label: _value.toStringAsFixed(2),
              onChangeStart: widget.enabled ? widget.onChangeStart : null,
              onChanged: widget.enabled
                  ? (value) {
                      setState(() => _value = value);
                      widget.onChanged?.call(value);
                    }
                  : null,
              onChangeEnd: widget.enabled ? widget.onChangeEnd : null,
            ),
          ),
          SizedBox(
            width: 48,
            child: Semantics(
              button: widget.enabled,
              label: 'Set exact value',
              value: _value.toStringAsFixed(2),
              child: Tooltip(
                message: widget.enabled ? 'Set exact value' : '',
                child: GestureDetector(
                  key: const ValueKey('filter_slider_value_button'),
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.enabled ? _editExactValue : null,
                  child: Text(
                    _value.toStringAsFixed(2),
                    textAlign: TextAlign.end,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

class _ExactValueDialog extends StatefulWidget {
  const _ExactValueDialog({
    required this.value,
    required this.min,
    required this.max,
  });

  final double value;
  final double min;
  final double max;

  @override
  State<_ExactValueDialog> createState() => _ExactValueDialogState();
}

class _ExactValueDialogState extends State<_ExactValueDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: _formatInputValue(widget.value),
  );
  String? _validationError;

  String _formatInputValue(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.005) return rounded.toInt().toString();
    return value.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || !parsed.isFinite) {
      setState(() => _validationError = 'Enter a valid number');
      return;
    }
    Navigator.of(context).pop(
      parsed.clamp(widget.min, widget.max).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set exact value'),
      content: TextField(
        key: const ValueKey('filter_slider_exact_input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: widget.min < 0,
        ),
        decoration: InputDecoration(
          labelText: 'Value',
          helperText:
              '${_formatInputValue(widget.min)} to ${_formatInputValue(widget.max)}',
          errorText: _validationError,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('filter_slider_exact_apply'),
          onPressed: _submit,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
