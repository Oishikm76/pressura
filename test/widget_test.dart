// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pressura/main.dart';

void main() {
  testWidgets('app builds', (tester) async {
    await tester.pumpWidget(const PressuraApp());
    expect(find.text('Pressura — Newmark Influence Chart'), findsOneWidget);
  });
}
