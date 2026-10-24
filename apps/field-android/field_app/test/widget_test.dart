// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:field_app/main.dart';

void main() {
  testWidgets('crew identity is displayed as a municipal ID card', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CrewIdentityCard(
            name: 'Asha Kumar',
            role: 'Crew Member',
            municipalId: 'CREW-1024',
            email: 'crew-1024@crew.drainrank.com',
            initials: 'AK',
            avatarColor: Color(0xFF0F766E),
          ),
        ),
      ),
    );

    expect(find.text('Asha Kumar'), findsOneWidget);
    expect(find.text('Crew Member'), findsOneWidget);
    expect(find.text('CREW-1024'), findsOneWidget);
    expect(find.text('AK'), findsOneWidget);
    expect(find.text('MUNICIPAL ID'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin can open and validate the crew account form', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: AdminDashboardPage()));

    await tester.tap(find.text('Add crew member'));
    await tester.pumpAndSettle();

    expect(find.text('Add crew member'), findsNWidgets(2));
    expect(find.text('Municipal ID'), findsOneWidget);
    expect(find.text('Full name'), findsOneWidget);
    expect(find.text('Temporary password'), findsOneWidget);
    expect(
      find.textContaining('credentials will be shown once'),
      findsOneWidget,
    );

    final createButton = find.text('Create account');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('letters, numbers, or hyphens'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crew login requests a Municipal ID and password', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CrewLoginPage()));
    expect(find.text('Municipal Crew Login'), findsOneWidget);
    expect(find.text('Municipal ID'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('field debug previews require the shared demo PIN', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var debugModeEnabled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: CrewDebugToolPage(
          onDebugModeChanged: (enabled) => debugModeEnabled = enabled,
        ),
      ),
    );

    expect(find.text('Local demo previews'), findsNothing);
    await tester.enterText(find.byType(TextField), '00000000');
    await tester.tap(find.text('Unlock local previews'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect demo PIN.'), findsOneWidget);
    expect(debugModeEnabled, isFalse);

    await tester.enterText(find.byType(TextField), '12345678');
    await tester.tap(find.text('Unlock local previews'));
    await tester.pumpAndSettle();
    expect(find.text('Local demo previews'), findsOneWidget);
    expect(find.text('Direct cleaning report preview'), findsOneWidget);
    expect(find.textContaining('Preview-only controls.'), findsOneWidget);
    expect(debugModeEnabled, isTrue);
    expect(tester.takeException(), isNull);
  });
}
