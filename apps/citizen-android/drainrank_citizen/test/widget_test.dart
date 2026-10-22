import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drainrank_citizen/main.dart';
import 'package:drainrank_citizen/models/citizen_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'phone auth offers sign-in and account creation without overflow',
    (tester) async {
      await _setSmallViewport(tester);
      await tester.pumpWidget(_scaledApp(const CitizenPhoneAuthPage()));

      expect(find.text('Citizen sign in'), findsOneWidget);
      expect(find.text('Phone number'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Create account'));
      await tester.pump();

      expect(find.text('Create your citizen account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('report form urgency selector fits a narrow, scaled viewport', (
    tester,
  ) async {
    await _setSmallViewport(tester);
    await tester.pumpWidget(
      _scaledApp(
        ReportIssueTab(deviceId: 'test-device', onReportSubmitted: () {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('3. High-Urgency Flag'),
      find.byType(ListView),
      const Offset(0, -400),
    );
    expect(find.text('3. High-Urgency Flag'), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<UrgencyConsequence>),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final urgencyDropdown = find.byType(
      DropdownButtonFormField<UrgencyConsequence>,
    );
    await tester.ensureVisible(urgencyDropdown);
    await tester.pumpAndSettle();
    await tester.tap(urgencyDropdown);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('report status cards fit a narrow, scaled viewport', (
    tester,
  ) async {
    final report = CitizenReport(
      reportId: 'REP-20261016-VERY-LONG-REPORT-IDENTIFIER',
      deviceId: 'test-device',
      linkedDrainId: 'PROVISIONAL-DRAIN-PIN-WITH-A-LONG-IDENTIFIER',
      latitude: 28.6139,
      longitude: 77.2090,
      gpsAccuracyMeters: 4.5,
      capturedAt: DateTime(2026, 10, 16),
      uploadedAt: DateTime(2026, 10, 16),
      imagePath: 'missing-test-image.jpg',
      imageSha256Hash: 'a' * 64,
      imageQualityPassed: true,
      imageLuminance: 0.5,
      issueCategory: IssueCategory.overflow,
      isUrgentFlagged: true,
      urgencyConsequence: UrgencyConsequence.criticalHospitalSchool,
      description: 'Long report used to exercise responsive status rendering.',
      status: ReportWorkflowStatus.underVerification,
      estimatedPriorityScore: 80,
    );
    SharedPreferences.setMockInitialValues({
      'drainrank_local_reports_v1': CitizenReport.encodeList([report]),
    });
    await _setSmallViewport(tester);
    await tester.pumpWidget(_scaledApp(const TrackStatusTab()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Logged Reports (1)'), findsOneWidget);
    expect(find.textContaining('URGENT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings screen fits a narrow, scaled viewport', (tester) async {
    await _setSmallViewport(tester);
    await tester.pumpWidget(
      _scaledApp(const DrainRankUtilityPage(title: 'Settings')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preferences'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _setSmallViewport(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 640);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _scaledApp(Widget child) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(
      size: Size(320, 640),
      textScaler: TextScaler.linear(1.5),
    ),
    child: child,
  ),
);
