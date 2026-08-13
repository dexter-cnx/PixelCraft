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

  String _formatValue(double value) {
    final rounded = value.roundToDouble();
    if ((value - rounded).abs() < 0.005) return rounded.toInt().toString();
    return value.toStringAsFixed(2);
  }

  Future<void> _editExactValue() async {
    if (!widget.enabled) return;

    final controller = TextEditingController(text: _formatValue(_value));
    String? validationError;
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Set exact value'),
          content: TextField(
            key: const ValueKey('filter_slider_exact_input'),
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              decimal: true,
              signed: widget.min < 0,
            ),
            decoration: InputDecoration(
              labelText: 'Value',
              helperText:
                  '${_formatValue(widget.min)} to ${_formatValue(widget.max)}',
              errorText: validationError,
            ),
            onSubmitted: (_) {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed == null || !parsed.isFinite) {
                setDialogState(() => validationError = 'Enter a valid number');
                return;
              }
              Navigator.of(dialogContext).pop(
                parsed.clamp(widget.min, widget.max).toDouble(),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('filter_slider_exact_apply'),
              onPressed: () {
                final parsed = double.tryParse(controller.text.trim());
                if (parsed == null || !parsed.isFinite) {
                  setDialogState(
                    () => validationError = 'Enter a valid number',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(
                  parsed.clamp(widget.min, widget.max).toDouble(),
                );
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

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
              label: _formatValue(_value),
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
            width: 64,
            child: TextButton(
              key: const ValueKey('filter_slider_value_button'),
              onPressed: widget.enabled ? _editExactValue : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(48, 40),
              ),
              child: Text(
                _formatValue(_value),
                textAlign: TextAlign.end,
              ),
            ),
          ),
        ],
      );
}
