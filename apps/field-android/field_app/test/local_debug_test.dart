import 'package:field_app/local_debug_demo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'local field workflow reports, verifies, and awards demo credits',
    (tester) async {
      await tester.pumpWidget(const LocalFieldDebugApp());
      expect(find.text('Local field test workspace'), findsOneWidget);
      expect(find.text('Send local report to queue'), findsNothing);

      await tester.enterText(find.byType(TextField), '12345678');
      await tester.tap(find.text('Unlock local tests'));
      await tester.pumpAndSettle();
      expect(find.text('Assigned tasks'), findsOneWidget);

      await tester.tap(find.text('Report').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Location or landmark'),
        'Market road',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Issue details'),
        'Blocked drain needs cleaning',
      );
      await tester.tap(find.text('Send local report to queue'));
      await tester.pumpAndSettle();

      expect(find.text('Blocked drain'), findsOneWidget);
      expect(find.textContaining('Awaiting verification'), findsOneWidget);
      await tester.tap(find.text('Verify · award 120 credits'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Status: Verified'), findsOneWidget);
      expect(find.textContaining('Local credits awarded: 120'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
