import 'package:chunky_cat_budg/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets('budget app starts on login screen', (tester) async {
    await tester.pumpWidget(const ChunkyCatBudgApp());
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Chunky Cat Budget'), findsOneWidget);
  });
  testWidgets('saving a reduced paycheck warns and navigates to chunks', (
    tester,
  ) async {
    int? destination;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PaycheckSetupScreen(
            api: _ShortageApi(),
            data: {
              'accounts': [
                {'id': 1, 'name': 'Checking', 'is_active': true},
              ],
              'paycheck_profiles': [
                {
                  'id': 1,
                  'name': 'Pay',
                  'net_pay_amount': 1000,
                  'default_account_id': 1,
                },
              ],
            },
            canEdit: true,
            refresh: () {},
            goTo: (index) => destination = index,
          ),
        ),
      ),
    );
    final amount = find.widgetWithText(TextField, 'Net paycheck amount');
    await tester.enterText(amount, '500');
    final save = find.text('Save Profile');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Readjust Chunks'), findsOneWidget);
    expect(destination, isNull);
    await tester.tap(find.text('Go to Chunks'));
    await tester.pumpAndSettle();
    expect(destination, 4);
  });
}

class _ShortageApi extends BudgetApi {
  @override
  Future<dynamic> post(String path, Map<String, dynamic> body) async => {
    'id': 1,
    'chunk_total': 600,
    'chunk_shortage': 100,
  };
}
