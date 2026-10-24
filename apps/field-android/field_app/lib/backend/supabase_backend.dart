import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get fieldBackend => Supabase.instance.client;

class FieldTaskRecord {
  const FieldTaskRecord({required this.id, required this.values});

  final String id;
  final Map<String, dynamic> values;

  Map<String, dynamic> data() => values;
}

extension FieldUserProperties on User {
  String get uid => id;

  String? get displayName => userMetadata?['full_name'] as String?;
}

Stream<List<FieldTaskRecord>> fieldTasksStream() => fieldBackend
    .from('field_tasks')
    .stream(primaryKey: ['id'])
    .map(
      (rows) => rows
          .map(
            (row) => FieldTaskRecord(
              id: row['id'] as String,
              values: fieldTaskFromRow(row),
            ),
          )
          .toList(),
    );

Stream<List<Map<String, dynamic>>> fieldWorkUpdatesStream() => fieldBackend
    .from('field_work_updates')
    .stream(primaryKey: ['id'])
    .map((rows) => rows.map(fieldWorkUpdateFromRow).toList());

Stream<List<Map<String, dynamic>>> fieldCreditsStream() {
  late StreamSubscription<List<Map<String, dynamic>>> taskSubscription;
  late StreamSubscription<List<Map<String, dynamic>>> reportSubscription;
  List<Map<String, dynamic>>? taskCredits;
  List<Map<String, dynamic>>? reportCredits;
  final output = StreamController<List<Map<String, dynamic>>>();

  void emitIfReady() {
    if (taskCredits != null && reportCredits != null) {
      output.add([...taskCredits!, ...reportCredits!]);
    }
  }

  taskSubscription = fieldBackend
      .from('credit_awards')
      .stream(primaryKey: ['id'])
      .map((rows) => rows.map(fieldCreditFromRow).toList())
      .listen(
        (rows) {
          taskCredits = rows;
          emitIfReady();
        },
        onError: output.addError,
      );
  reportSubscription = fieldBackend
      .from('direct_cleaning_report_credits')
      .stream(primaryKey: ['report_id'])
      .map(
        (rows) => rows
            .map(
              (row) => {
                ...row,
                'taskId': 'direct-report:${row['report_id']}',
                'crewUid': row['user_id'],
                'approvedAt': row['created_at'],
                'type': 'directReport',
              },
            )
            .toList(),
      )
      .listen(
        (rows) {
          reportCredits = rows;
          emitIfReady();
        },
        onError: output.addError,
      );

  output.onCancel = () async {
    await taskSubscription.cancel();
    await reportSubscription.cancel();
  };
  return output.stream;
}

Stream<List<Map<String, dynamic>>> fieldLeaveRequestsStream() => fieldBackend
    .from('leave_requests')
    .stream(primaryKey: ['id'])
    .map((rows) => rows.map(fieldLeaveRequestFromRow).toList());

Map<String, dynamic> fieldTaskFromRow(Map<String, dynamic> row) => {
  ...row,
  'dateKey': row['date_key']?.toString(),
  'startTime': row['start_time'],
  'endTime': row['end_time'],
  'assignedToUid': row['assigned_to_uid'],
  'crewMembers': row['crew_members'],
  'workWindowStart': row['work_window_start'],
  'workWindowEnd': row['work_window_end'],
  'dailyOverdueDeduction': row['daily_overdue_deduction'],
};

Map<String, dynamic> fieldWorkUpdateFromRow(Map<String, dynamic> row) => {
  ...row,
  'taskId': row['task_id'],
  'submittedByUid': row['submitted_by_uid'],
  'photoUrl': row['photo_url'],
  'photoPath': row['photo_path'],
  'capturedAt': row['captured_at'],
  'submittedAt': row['submitted_at'],
  'submittedOverdue': row['submitted_overdue'],
  'accuracyMeters': row['accuracy_meters'],
};

Map<String, dynamic> fieldCreditFromRow(Map<String, dynamic> row) => {
  if (row['payload'] is Map)
    ...Map<String, dynamic>.from(row['payload'] as Map),
  ...row,
  'taskId': row['task_id'],
  'crewUid': row['user_id'],
  'approvedAt': row['created_at'],
};

Map<String, dynamic> fieldLeaveRequestFromRow(Map<String, dynamic> row) => {
  if (row['payload'] is Map)
    ...Map<String, dynamic>.from(row['payload'] as Map),
  ...row,
  'crewUid': row['user_id'],
  'requestedAt': row['created_at'],
};

DateTime? fieldDateTime(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}

String internalEmailForMunicipalId(String municipalId) =>
    '${municipalId.trim().toLowerCase()}@crew.drainrank.com';

Future<bool> isFieldAdministrator(String userId) async {
  final membership = await fieldBackend
      .from('profiles')
      .select('id')
      .eq('id', userId)
      .eq('role', 'admin')
      .eq('access_blocked', false)
      .maybeSingle();
  return membership != null;
}

Future<int> processOverdueDeductionsForAdmin() async {
  final count = await fieldBackend.rpc('process_field_overdue_deductions');
  if (count is! int) {
    throw StateError('Backend did not return the overdue deduction count.');
  }
  return count;
}
