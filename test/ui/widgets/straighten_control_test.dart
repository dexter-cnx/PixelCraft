import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/widgets/straighten_control.dart';

void main() {
  Widget harness({
    double value = 0,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: StraightenControl(
            value: value,
            enabled: true,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ),
    );
  }

  testWidgets('exact straighten entry previews and commits through existing path',
      (tester) async {
    double? previewed;
    double? committed;
    await tester.pumpWidget(
      harness(
        onChanged: (value) => previewed = value,
        onChangeEnd: (value) => committed = value,
      ),
    );

    expect(find.text('0.0°'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('straighten_exact_value_button')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('straighten_exact_input')),
      '-2.75',
    );
    await tester.tap(find.byKey(const ValueKey('straighten_exact_apply')));
    await tester.pumpAndSettle();

    expect(previewed, -2.75);
    expect(committed, -2.75);
  });

  testWidgets('exact straighten entry validates and clamps to supported range',
      (tester) async {
    double? committed;
    await tester.pumpWidget(
      harness(
        onChanged: (_) {},
        onChangeEnd: (value) => committed = value,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('straighten_exact_value_button')),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('straighten_exact_input'));

    await tester.enterText(input, 'oops');
    await tester.tap(find.byKey(const ValueKey('straighten_exact_apply')));
    await tester.pump();
    expect(find.text('Enter a valid angle'), findsOneWidget);
    expect(committed, isNull);

    await tester.enterText(input, '40');
    await tester.tap(find.byKey(const ValueKey('straighten_exact_apply')));
    await tester.pumpAndSettle();

    expect(committed, 15);
  });
}
