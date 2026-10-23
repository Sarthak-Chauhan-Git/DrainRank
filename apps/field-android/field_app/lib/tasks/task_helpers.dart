part of '../main.dart';

DateTime? _parseTaskDate(dynamic rawDate) {
  final parsed = fieldDateTime(rawDate);
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
    task['workWindowStart'] is String && task['workWindowEnd'] is String;

/// One shared Supabase task can be assigned to multiple crew members.
/// Each crew member's photo submission is stored separately in `workUpdates`.
/// Applies idempotent, admin-authorized daily overdue deductions from each task's
/// `dailyOverdueDeduction` field. Call explicitly from the admin review screen.
/// A separate immutable ledger document is created for each crew/task/day.
String _taskDateLabel(dynamic rawDate) {
  if (rawDate is String) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed != null) return _prettyDate(parsed);
  }
  return 'Date not specified';
}

/// Live, per-crew admin award display for this task.
class _TaskAwardCredits extends StatelessWidget {
  const _TaskAwardCredits({required this.taskId, required this.uid});
  final String taskId;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: fieldCreditsStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Credits unavailable');
        var total = 0;
        for (final row in (snapshot.data ?? const []).where(
          (row) => row['taskId'] == taskId && row['crewUid'] == uid,
        )) {
          final amount = row['credits'];
          if (amount is int) total += amount;
        }
        final isPenalty = total < 0;
        final hasAward = total > 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPenalty
                  ? Icons.trending_down
                  : hasAward
                  ? Icons.workspace_premium_outlined
                  : Icons.schedule_outlined,
              size: 20,
              color: isPenalty
                  ? const Color(0xFFB91C1C)
                  : hasAward
                  ? const Color(0xFFF59E0B)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              total < 0
                  ? '$total credits'
                  : hasAward
                  ? '+$total credits'
                  : '0 credits',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isPenalty ? const Color(0xFFB91C1C) : null,
              ),
            ),
          ],
        );
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
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

String _formatCapturedAt(dynamic value) {
  final date = fieldDateTime(value);
  if (date != null) {
    return '${_prettyDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  return 'Not recorded';
}
