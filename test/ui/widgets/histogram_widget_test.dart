import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelcraft/ui/widgets/histogram_widget.dart';

void main() {
  List<int> bins() => List<int>.generate(768, (index) => (index % 256) + 1);

  testWidgets('histogram channel menu switches RGB view to a single channel',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: HistogramWidget(bins: bins()),
          ),
        ),
      ),
    );

    final label = find.byKey(const ValueKey('histogram_channel_label'));
    expect(label, findsOneWidget);
    expect(tester.widget<Text>(label).data, 'RGB');

    await tester.tap(find.byKey(const ValueKey('histogram_channel_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Red'));
    await tester.pumpAndSettle();

    expect(label, findsOneWidget);
    expect(tester.widget<Text>(label).data, 'R');
  });

  testWidgets('histogram channel selection stays presentation-only',
      (tester) async {
    final source = bins();
    await tester.pumpWidget(
      MaterialApp(
        home: HistogramWidget(bins: source),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('histogram_channel_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blue'));
    await tester.pumpAndSettle();

    expect(source.length, 768);
    expect(source.first, 1);
    expect(source.last, 256);
  });
}
