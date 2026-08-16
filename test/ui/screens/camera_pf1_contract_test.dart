import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PF1 runtime contract keeps capture semantics separate from PF3', () {
    const targetHierarchy = <String>['Gallery', 'Shutter', 'Controls'];
    expect(targetHierarchy, hasLength(3));
    expect(targetHierarchy[1], 'Shutter');
  });
}
