import 'package:field_app/services/priority_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('priority score follows citizen formula with 500m facility flag', () {
    final regularScore = FieldPriorityAnalyzer.priorityScore(
      issueCategory: 'blocked_drain',
      urgent: false,
    );
    final urgentScore = FieldPriorityAnalyzer.priorityScore(
      issueCategory: 'blocked_drain',
      urgent: true,
    );
    final otherScore = FieldPriorityAnalyzer.priorityScore(
      issueCategory: 'other',
      urgent: false,
    );

    expect(regularScore, 72.7);
    expect(urgentScore, 87.8);
    expect(otherScore, 52.8);
    expect(urgentScore, greaterThan(regularScore));
  });

  test('known drain catchment weight is included in score', () {
    const drain = FieldDrainMatch(
      drainId: 'DR-1024',
      name: 'Hospital Road Main Inlet',
      latitude: 28.9845,
      longitude: 77.7064,
      catchmentProxy: 1,
    );

    expect(
      FieldPriorityAnalyzer.priorityScore(
        issueCategory: 'blocked_drain',
        urgent: true,
        matchedDrain: drain,
      ),
      100,
    );
  });
}
