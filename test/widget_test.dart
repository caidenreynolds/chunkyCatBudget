import 'package:chunky_cat_budg/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('budget app renders without a live API', (tester) async {
    await tester.pumpWidget(const ChunkyCatBudgApp());
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
  });
}
