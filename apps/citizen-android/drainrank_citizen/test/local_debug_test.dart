import 'package:drainrank_citizen/local_debug_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('local citizen workflow stays in-memory behind demo PIN', (
    tester,
  ) async {
    await tester.pumpWidget(const LocalCitizenDebugApp());
    expect(find.text('Local citizen test workspace'), findsOneWidget);
    expect(find.text('Submit local report'), findsNothing);

    await tester.enterText(find.byType(TextField), '12345678');
    await tester.tap(find.text('Unlock local tests'));
    await tester.pumpAndSettle();
    expect(find.text('Report a drainage issue'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Location or landmark'),
      'Market road',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Issue details'),
      'Drain is blocked',
    );
    await tester.tap(find.text('Submit local report'));
    await tester.pumpAndSettle();

    expect(find.textContaining('LOCAL-'), findsOneWidget);
    expect(find.text('Complaint received'), findsOneWidget);
    expect(find.textContaining('No server was contacted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
