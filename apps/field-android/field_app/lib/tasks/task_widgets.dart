part of '../main.dart';

List<Map<String, dynamic>> _sampleTasksForDate(String dateKey) {
  // Demonstration data only: these tasks are not written to Supabase.
  return [
    {
      'title': 'Clean roadside drain',
      'startTime': '08:00 AM',
      'endTime': '09:30 AM',
      'location': 'Ward 12, near Community Park',
      'description': 'Remove waste and blockage. Keep the footpath clear.',
      'status': 'Pending',
      'dateKey': dateKey,
    },
    {
      'title': 'Remove drain blockage',
      'startTime': '10:00 AM',
      'endTime': '11:00 AM',
      'location': 'Main Market Road, opposite Bus Stop',
      'description': 'Check water flow and collect removed waste safely.',
      'status': 'In Progress',
      'dateKey': dateKey,
    },
    {
      'title': 'Inspect and rinse drain',
      'startTime': '01:00 PM',
      'endTime': '02:00 PM',
      'location': 'Lane 4, Shastri Nagar',
      'description': 'Confirm the drain is flowing freely after cleaning.',
      'status': 'Completed',
      'dateKey': dateKey,
    },
  ];
}

class _DemoTaskPreview extends StatelessWidget {
  const _DemoTaskPreview({required this.tasks, required this.backendError});

  final List<Map<String, dynamic>> tasks;
  final bool backendError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: colors.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                backendError
                    ? Icons.cloud_off_outlined
                    : Icons.visibility_outlined,
                color: colors.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  backendError
                      ? 'Showing sample tasks because Supabase tasks could not be loaded. These examples are not real assignments. Check your connection and field-task access.'
                      : 'Sample preview only — these examples are not saved in Supabase. Real assignments appear here when added by an administrator.',
                  style: TextStyle(color: colors.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < tasks.length; i++)
          _DrainTaskCard(data: tasks[i], number: i + 1),
      ],
    );
  }
}

class _DateTab extends StatelessWidget {
  const _DateTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.surfaceContainerHighest : colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              Icon(icon, size: 23),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskMessage extends StatelessWidget {
  const _TaskMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
        child: Column(
          children: [
            Icon(icon, size: 46),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 7),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Compact list item: only title and scheduled time.
class _DrainTaskCard extends StatelessWidget {
  const _DrainTaskCard({
    required this.data,
    required this.number,
    this.onTap,
    this.taskId,
    this.currentUserUid,
    this.showCredits = false,
    this.isOverdue = false,
    this.showDeadline = false,
    this.evidenceStatus,
  });

  final Map<String, dynamic> data;
  final int number;
  final VoidCallback? onTap;
  final String? taskId;
  final String? currentUserUid;
  final bool showCredits;
  final bool isOverdue;
  final bool showDeadline;
  final String? evidenceStatus;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Clean assigned drain').toString();
    final start = (data['startTime'] ?? '').toString();
    final end = (data['endTime'] ?? '').toString();
    final time = start.isEmpty
        ? 'Time not specified'
        : (end.isEmpty ? start : '$start – $end');
    final deadline = fieldDateTime(data['workWindowEnd']);
    final deadlineText = deadline == null
        ? 'Due ${_taskDateLabel(data['dateKey'])}${end.isEmpty ? '' : ' · $end'}'
        : 'Due ${_prettyDate(deadline)} · ${TimeOfDay.fromDateTime(deadline).format(context)}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        leading: const CircleAvatar(child: Icon(Icons.water_drop_outlined)),
        title: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(time, style: Theme.of(context).textTheme.bodySmall),
            if (evidenceStatus != null) ...[
              const SizedBox(height: 4),
              Text(
                switch (evidenceStatus) {
                  'accepted' => 'Evidence accepted',
                  'pending' => 'Evidence pending review',
                  'rework_requested' => 'Rework requested',
                  'location_mismatch' => 'Location clarification requested',
                  _ => 'Evidence submitted',
                },
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: evidenceStatus == 'accepted'
                      ? const Color(0xFF059669)
                      : const Color(0xFF475569),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (showDeadline)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  deadlineText,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            if (isOverdue)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OVERDUE · Assigned ${_taskDateLabel(data['dateKey'])}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB91C1C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Warning: a daily credit deduction may apply until work is submitted.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: const Color(0xFFB91C1C)),
                    ),
                  ],
                ),
              ),
            if (taskId != null && currentUserUid != null) ...[
              const SizedBox(height: 4),
              Text(
                "Shared task status: ${(data['status'] ?? 'Pending').toString()}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (showCredits) ...[
                const SizedBox(height: 8),
                StreamBuilder<List<Map<String, dynamic>>>(
                  stream: fieldCreditsStream(),
                  builder: (context, awardSnapshot) {
                    if (awardSnapshot.hasError) {
                      return Text(
                        'Credits unavailable',
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    }
                    var total = 0;
                    var penaltyTotal = 0;
                    for (final entry in (awardSnapshot.data ?? const []).where(
                      (row) =>
                          row['taskId'] == taskId &&
                          row['crewUid'] == currentUserUid,
                    )) {
                      final value = entry['credits'];
                      if (value is! int) continue;
                      total += value;
                      if (entry['type'] == 'overduePenalty')
                        penaltyTotal += value;
                    }
                    final rate = data['dailyOverdueDeduction'] is int
                        ? data['dailyOverdueDeduction'] as int
                        : 0;
                    final day = _parseTaskDate(data['dateKey']);
                    final elapsedDays = day != null && isOverdue
                        ? _todayOnly().difference(day).inDays
                        : 0;
                    final estimatedPenalty = rate * elapsedDays;
                    if (isOverdue && penaltyTotal < 0) {
                      return Row(
                        children: [
                          Icon(
                            Icons.trending_down,
                            size: 18,
                            color: const Color(0xFFB91C1C),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$penaltyTotal credits',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFB91C1C),
                            ),
                          ),
                        ],
                      );
                    }
                    if (isOverdue && estimatedPenalty > 0) {
                      return Row(
                        children: [
                          Icon(
                            Icons.trending_down,
                            size: 18,
                            color: const Color(0xFFB91C1C),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '−$estimatedPenalty credits (pending)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFB91C1C),
                            ),
                          ),
                        ],
                      );
                    }
                    if (total < 0) {
                      return Row(
                        children: [
                          Icon(
                            Icons.trending_down,
                            size: 18,
                            color: const Color(0xFFB91C1C),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$total credits',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFFB91C1C),
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Icon(
                          total > 0
                              ? Icons.workspace_premium_outlined
                              : Icons.schedule_outlined,
                          size: 18,
                          color: total > 0
                              ? const Color(0xFFF59E0B)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          total > 0 ? '+$total credits' : '0 credits',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    );
                  },
                ),
              ],
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: fieldWorkUpdatesStream(),
                builder: (context, snapshot) {
                  final submitted =
                      snapshot.hasData &&
                      snapshot.data!.any(
                        (row) =>
                            row['taskId'] == taskId &&
                            row['submittedByUid'] == currentUserUid,
                      );
                  return Text(
                    submitted
                        ? 'Your image upload: Submitted'
                        : 'Your image upload: Pending',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: submitted
                          ? const Color(0xFF059669)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      ),
    );
  }
}
