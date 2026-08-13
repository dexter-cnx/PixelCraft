import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/widgets/filter_slider.dart';

void main() {
  Widget harness({
    double value = 0,
    double min = -5,
    double max = 5,
    required ValueChanged<double> onChangeEnd,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: FilterSlider(
            value: value,
            min: min,
            max: max,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ),
    );
  }

  testWidgets('exact value entry commits through the existing change-end path',
      (tester) async {
    double? committed;
    await tester.pumpWidget(
      harness(onChangeEnd: (value) => committed = value),
    );

    await tester.tap(find.byKey(const ValueKey('filter_slider_value_button')));
    await tester.pumpAndSettle();
    expect(find.text('Set exact value'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('filter_slider_exact_input')),
      '2.75',
    );
    await tester.tap(find.byKey(const ValueKey('filter_slider_exact_apply')));
    await tester.pumpAndSettle();

    expect(committed, 2.75);
    expect(find.text('2.75'), findsOneWidget);
  });

  testWidgets('exact value entry validates input and clamps to semantic bounds',
      (tester) async {
    double? committed;
    await tester.pumpWidget(
      harness(
        min: 0,
        max: 1,
        onChangeEnd: (value) => committed = value,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('filter_slider_value_button')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('filter_slider_exact_input'));

    await tester.enterText(input, 'not-a-number');
    await tester.tap(find.byKey(const ValueKey('filter_slider_exact_apply')));
    await tester.pump();
    expect(find.text('Enter a valid number'), findsOneWidget);
    expect(committed, isNull);

    await tester.enterText(input, '5');
    await tester.tap(find.byKey(const ValueKey('filter_slider_exact_apply')));
    await tester.pumpAndSettle();

    expect(committed, 1);
    expect(find.text('1'), findsOneWidget);
  });
}
