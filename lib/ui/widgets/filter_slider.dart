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
            child: Text(_value.toStringAsFixed(2), textAlign: TextAlign.end),
          ),
        ],
      );
}
