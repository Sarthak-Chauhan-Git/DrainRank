import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:drainrank_citizen/main.dart';
import 'package:drainrank_citizen/models/citizen_report.dart';
import 'package:drainrank_citizen/services/drainrank_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'email auth offers sign-in and account creation without overflow',
    (tester) async {
      await _setSmallViewport(tester);
      await tester.pumpWidget(_scaledApp(const CitizenEmailAuthPage()));

      expect(find.text('Citizen sign in'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Create account'));
      await tester.pump();

      expect(find.text('Create your citizen account'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('report form shows automatic urgency without manual controls', (
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
      find.text('Standard priority'),
      find.byType(ListView),
      const Offset(0, -400),
    );
    expect(find.text('Standard priority'), findsOneWidget);
    expect(
      find.byType(DropdownButtonFormField<UrgencyConsequence>),
      findsNothing,
    );
    expect(find.byType(Switch), findsNothing);
    final urgencyInfo = find.byTooltip('About automatic urgency');
    expect(urgencyInfo, findsOneWidget);
    await tester.tap(urgencyInfo);
    await tester.pumpAndSettle();
    expect(find.text('How is urgency assessed?'), findsOneWidget);
    expect(find.textContaining('within 500 metres'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('report status handles signed-out state with pull to refresh', (
    tester,
  ) async {
    await _setSmallViewport(tester);
    await tester.pumpWidget(_scaledApp(const TrackStatusTab()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Your reports (0)'), findsOneWidget);
    expect(find.text('Sign in to view your reports.'), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
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

  testWidgets('debug tool requires the demo PIN before showing controls', (
    tester,
  ) async {
    await _setSmallViewport(tester);
    await tester.pumpWidget(
      _scaledApp(const DrainRankUtilityPage(title: 'Debug Tool')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Demo and testing tools'), findsOneWidget);
    expect(find.text('Fixed report location'), findsNothing);

    await tester.enterText(find.byType(TextField), '00000000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Incorrect demo PIN.'), findsOneWidget);
    expect(find.text('Fixed report location'), findsNothing);

    await tester.enterText(find.byType(TextField), '12345678');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Fixed report location'), findsOneWidget);
    expect(find.text('Simulate report status'), findsOneWidget);
    expect(find.text('Your test reports'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('withdrawn reports round-trip through the local report model', () {
    final report = CitizenReport(
      reportId: 'REP-20261024-TEST',
      deviceId: 'test-device',
      linkedDrainId: 'PROVISIONAL-PIN',
      latitude: 28.6,
      longitude: 77.2,
      gpsAccuracyMeters: 5,
      capturedAt: DateTime.utc(2026, 10, 24),
      uploadedAt: DateTime.utc(2026, 10, 24),
      imagePath: '',
      imageSha256Hash: '',
      imageQualityPassed: true,
      imageLuminance: 120,
      issueCategory: IssueCategory.other,
      isUrgentFlagged: false,
      urgencyConsequence: UrgencyConsequence.standardResidential,
      description: 'Test report',
      status: ReportWorkflowStatus.withdrawn,
      estimatedPriorityScore: 42,
    );

    final decoded = CitizenReport.decodeList(CitizenReport.encodeList([report]))
        .single;

    expect(decoded.status, ReportWorkflowStatus.withdrawn);
  });

  test(
    'withdrawn reports do not block a new report at the same location',
    () async {
      final withdrawnReport = _sampleReport(
        status: ReportWorkflowStatus.withdrawn,
      );
      await DrainRankEngine.cacheReports([
        withdrawnReport,
      ], userId: 'test-user');

      final result = await DrainRankEngine.checkSameDeviceRadiusLock(
        currentLat: withdrawnReport.latitude,
        currentLng: withdrawnReport.longitude,
        deviceId: withdrawnReport.deviceId,
        userId: 'test-user',
      );

      expect(result.isBlocked, isFalse);
    },
  );

  test('active reports still block duplicate submissions', () async {
    final activeReport = _sampleReport(
      status: ReportWorkflowStatus.complaintReceived,
    );
    await DrainRankEngine.cacheReports([activeReport], userId: 'test-user');

    final result = await DrainRankEngine.checkSameDeviceRadiusLock(
      currentLat: activeReport.latitude,
      currentLng: activeReport.longitude,
      deviceId: activeReport.deviceId,
      userId: 'test-user',
    );

    expect(result.isBlocked, isTrue);
  });
}

CitizenReport _sampleReport({required ReportWorkflowStatus status}) {
  final now = DateTime.now();
  return CitizenReport(
    reportId: 'REP-TEST',
    deviceId: 'test-device',
    linkedDrainId: 'PROVISIONAL-PIN',
    latitude: 28.6,
    longitude: 77.2,
    gpsAccuracyMeters: 5,
    capturedAt: now,
    uploadedAt: now,
    imagePath: '',
    imageSha256Hash: '',
    imageQualityPassed: true,
    imageLuminance: 120,
    issueCategory: IssueCategory.other,
    isUrgentFlagged: false,
    urgencyConsequence: UrgencyConsequence.standardResidential,
    description: 'Test report',
    status: status,
    estimatedPriorityScore: 42,
  );
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
