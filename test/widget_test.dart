import 'package:chunky_cat_budg/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('budget app starts on login screen', (tester) async {
    await tester.pumpWidget(const ChunkyCatBudgApp());
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Chunky Cat Budget'), findsOneWidget);
  });
}
