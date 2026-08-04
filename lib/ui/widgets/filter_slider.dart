import 'dart:async';
import 'package:flutter/material.dart';

class FilterSlider extends StatefulWidget {
  const FilterSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  State<FilterSlider> createState() => _FilterSliderState();
}

class _FilterSliderState extends State<FilterSlider> {
  Timer? _frameThrottle;
  late double _value = widget.value;

  @override
  void didUpdateWidget(covariant FilterSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || oldWidget.min != widget.min || oldWidget.max != widget.max) {
      _value = widget.value.clamp(widget.min, widget.max);
    }
  }

  @override
  void dispose() {
    _frameThrottle?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Slider(
              value: _value.clamp(widget.min, widget.max),
              min: widget.min,
              max: widget.max,
              divisions: 100,
              label: _value.toStringAsFixed(2),
              onChangeStart: widget.onChangeStart,
              onChanged: (value) {
                setState(() => _value = value);
                _frameThrottle?.cancel();
                _frameThrottle = Timer(
                  const Duration(milliseconds: 16),
                  () => widget.onChanged(value),
                );
              },
              onChangeEnd: (value) {
                _frameThrottle?.cancel();
                // Render the exact final value before committing one history item.
                widget.onChanged(value);
                widget.onChangeEnd(value);
              },
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(_value.toStringAsFixed(2), textAlign: TextAlign.end),
          ),
        ],
      );
}
