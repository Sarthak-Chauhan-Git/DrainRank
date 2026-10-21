part of '../main.dart';

DateTime? _parseTaskDate(dynamic rawDate) {
  DateTime? parsed;
  if (rawDate is String) parsed = DateTime.tryParse(rawDate);
  if (rawDate is Timestamp) parsed = rawDate.toDate();
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime _todayOnly() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

bool isScheduledToday(dynamic dateKey) {
  final day = _parseTaskDate(dateKey);
  return day != null && day == _todayOnly();
}

bool isOverdueTaskDate(dynamic dateKey) {
  final day = _parseTaskDate(dateKey);
  return day != null && day.isBefore(_todayOnly());
}

bool isTodayOrOverdueTaskDate(dynamic dateKey) {
  final day = _parseTaskDate(dateKey);
  return day != null && !day.isAfter(_todayOnly());
}

/// Explicit task edit boundaries written by the administrator.
/// A task without these boundaries is read-only for server-enforced uploads.
bool hasEditWindow(Map<String, dynamic> task) =>
    task['workWindowStart'] is Timestamp && task['workWindowEnd'] is Timestamp;

/// One shared Firestore task document can be assigned to multiple crew UIDs.
/// Each crew member's photo submission is stored separately in `workUpdates`.
/// Applies idempotent, admin-authorized daily overdue deductions from each task's
/// `dailyOverdueDeduction` field. Call explicitly from the admin review screen.
/// A separate immutable ledger document is created for each crew/task/day.
Future<int> processOverdueDeductionsForAdmin(String adminUid) async {
  final db = FirebaseFirestore.instance;
  final today = _todayOnly();
  final tasks = await db.collection('tasks').get();
  var createdCount = 0;

  for (final taskDoc in tasks.docs) {
    final task = taskDoc.data();
    final taskDay = _parseTaskDate(task['dateKey']);
    final rate = task['dailyOverdueDeduction'];
    final assignedRaw = task['assignedToUid'];
    if (taskDay == null || !taskDay.isBefore(today) || rate is! int || rate <= 0 || assignedRaw is! List) {
      continue;
    }

    for (final uid in assignedRaw.whereType<String>()) {
      final submissions = await taskDoc.reference.collection('workUpdates')
          .where('submittedByUid', isEqualTo: uid).get();
      var cutoffDay = today;
      if (submissions.docs.isNotEmpty) {
        DateTime? firstSubmissionDay;
        for (final submission in submissions.docs) {
          final submittedAt = submission.data()['submittedAt'];
          if (submittedAt is! Timestamp) continue;
          final timestamp = submittedAt.toDate();
          final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
          if (firstSubmissionDay == null || day.isBefore(firstSubmissionDay)) {
            firstSubmissionDay = day;
          }
        }
        if (firstSubmissionDay != null) cutoffDay = firstSubmissionDay;
      }
      if (!cutoffDay.isAfter(taskDay)) continue;

      for (var penaltyDay = taskDay.add(const Duration(days: 1));
          !penaltyDay.isAfter(cutoffDay);
          penaltyDay = penaltyDay.add(const Duration(days: 1))) {
        final dayKey = _dateKey(penaltyDay);
        final penaltyId = 'overdue_${taskDoc.id}_$dayKey';
        final penaltyRef = db.collection('users').doc(uid)
            .collection('creditAwards').doc(penaltyId);
        final created = await db.runTransaction<bool>((tx) async {
          final prior = await tx.get(penaltyRef);
          if (prior.exists) return false;
          tx.set(penaltyRef, {
            'taskId': taskDoc.id,
            'taskTitle': (task['title'] ?? 'Assigned task').toString(),
            'crewUid': uid,
            'credits': -rate,
            'type': 'overduePenalty',
            'penaltyDate': dayKey,
            'dailyRate': rate,
            'approvedByUid': adminUid,
            'approvedAt': FieldValue.serverTimestamp(),
          });
          return true;
        });
        if (created) createdCount++;
      }
    }
  }
  return createdCount;
}

String _taskDateLabel(dynamic rawDate) {
  if (rawDate is String) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed != null) return _prettyDate(parsed);
  }
  if (rawDate is Timestamp) return _prettyDate(rawDate.toDate());
  return 'Date not specified';
}

/// Live, per-crew admin award display for this task.
class _TaskAwardCredits extends StatelessWidget {
  const _TaskAwardCredits({required this.taskId, required this.uid});
  final String taskId;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid)
          .collection('creditAwards').where('taskId', isEqualTo: taskId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Credits unavailable');
        var total = 0;
        for (final doc in snapshot.data?.docs ?? const []) {
          final amount = doc.data()['credits'];
          if (amount is int) total += amount;
        }
        final isPenalty = total < 0;
        final hasAward = total > 0;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isPenalty ? Icons.trending_down : hasAward
                ? Icons.workspace_premium_outlined : Icons.schedule_outlined,
            size: 20,
            color: isPenalty ? const Color(0xFFB91C1C) : hasAward
                ? const Color(0xFFF59E0B) : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            total < 0 ? '$total credits' : hasAward ? '+$total credits' : '0 credits',
            style: TextStyle(fontWeight: FontWeight.bold,
                color: isPenalty ? const Color(0xFFB91C1C) : null),
          ),
        ]);
      },
    );
  }
}

class _GeoMetadataRow extends StatelessWidget {
  const _GeoMetadataRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 92, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(value)),
    ]),
  );
}

String _formatCapturedAt(dynamic value) {
  if (value is Timestamp) {
    final date = value.toDate();
    return '${_prettyDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  return 'Not recorded';
}
