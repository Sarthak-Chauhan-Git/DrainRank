part of '../main.dart';

/// Personal task history for the past 1, 3, or 6 calendar months.
/// "Done by you" means this member submitted at least one work update;
/// it does NOT mean the administrator marked the shared task Completed.
class CrewActivityPage extends StatefulWidget {
  const CrewActivityPage({
    super.key,
    required this.currentUserUid,
    this.embedded = false,
  });
  final String currentUserUid;
  final bool embedded;

  @override
  State<CrewActivityPage> createState() => _CrewActivityPageState();
}

class _ActivitySubmissionInfo {
  const _ActivitySubmissionInfo({
    required this.submitted,
    required this.submittedOverdue,
    this.submittedAt,
    this.reviewStatus,
  });

  final bool submitted;
  final bool submittedOverdue;
  final DateTime? submittedAt;
  final String? reviewStatus;
}

class _CrewActivityPageState extends State<CrewActivityPage> {
  int _months = 1;
  late final Stream<List<FieldTaskRecord>> _assignedTasks;
  late final Stream<List<Map<String, dynamic>>> _workUpdates;

  @override
  void initState() {
    super.initState();
    _assignedTasks = fieldTasksStream();
    _workUpdates = fieldWorkUpdatesStream();
  }

  DateTime _earliestDay(DateTime today) {
    // Clamp the date to the final day of the earlier month when necessary.
    final monthStart = DateTime(today.year, today.month - _months, 1);
    final nextMonth = DateTime(monthStart.year, monthStart.month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1)).day;
    return DateTime(
      monthStart.year,
      monthStart.month,
      today.day < lastDay ? today.day : lastDay,
    );
  }

  DateTime? _taskDay(Map<String, dynamic> task) {
    final key = task['dateKey'];
    if (key is String) return DateTime.tryParse(key);
    return null;
  }

  String _taskTime(Map<String, dynamic> task) {
    final start = (task['startTime'] ?? '').toString().trim();
    final end = (task['endTime'] ?? '').toString().trim();
    if (start.isEmpty) return 'Time not specified';
    return end.isEmpty ? start : '$start - $end';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final earliest = _earliestDay(todayOnly);
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('Your Activity')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: fieldCreditsStream(),
        builder: (context, awardsSnapshot) {
          if (awardsSnapshot.hasError) {
            return Center(
              child: Text('Unable to load credits: ${awardsSnapshot.error}'),
            );
          }
          final awards = (awardsSnapshot.data ?? [])
              .where((row) => row['crewUid'] == widget.currentUserUid)
              .toList();
          final creditsByTask = <String, int>{};
          final positiveAwardTasks = <String>{};
          final penaltyByTask = <String, int>{};
          var periodCredits = 0;
          final now = DateTime.now();
          final earliestAward = _earliestDay(
            DateTime(now.year, now.month, now.day),
          );
          for (final data in awards) {
            final value = data['credits'];
            final granted = fieldDateTime(data['approvedAt']);
            if (value is! int || granted == null) continue;
            // Penalties belong to the actual overdue date, even if an admin
            // processes the ledger later. Positive awards use approval date.
            DateTime grantDate;
            if (data['type'] == 'overduePenalty' &&
                data['penaltyDate'] is String) {
              grantDate =
                  DateTime.tryParse(data['penaltyDate'] as String) ?? granted;
            } else {
              grantDate = granted;
            }
            final grantedDay = DateTime(
              grantDate.year,
              grantDate.month,
              grantDate.day,
            );
            if (!grantedDay.isBefore(earliestAward) &&
                !grantedDay.isAfter(DateTime(now.year, now.month, now.day))) {
              periodCredits += value;
            }
            final taskId = (data['taskId'] ?? data['id']).toString();
            creditsByTask.update(
              taskId,
              (current) => current + value,
              ifAbsent: () => value,
            );
            if (data['type'] == 'overduePenalty' || value < 0) {
              penaltyByTask.update(
                taskId,
                (current) => current + value,
                ifAbsent: () => value,
              );
            } else if (value > 0) {
              positiveAwardTasks.add(taskId);
            }
          }
          return StreamBuilder<List<FieldTaskRecord>>(
            stream: _assignedTasks,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Unable to load activity: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: _workUpdates,
                builder: (context, updatesSnapshot) {
                  if (updatesSnapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Unable to read personal work updates: '
                          '${updatesSnapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (!updatesSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final updatesByTask = <String, _ActivitySubmissionInfo>{
                    for (final update in updatesSnapshot.data!)
                      if (update['submittedByUid'] == widget.currentUserUid &&
                          update['taskId'] is String)
                        update['taskId'] as String: _ActivitySubmissionInfo(
                          submitted: true,
                          submittedOverdue: update['submittedOverdue'] == true,
                          submittedAt: fieldDateTime(update['submittedAt']),
                          reviewStatus: update['review_status'] as String?,
                        ),
                  };
                  final docs = snapshot.data!.where((doc) {
                    final day = _taskDay(doc.data());
                    final submission = updatesByTask[doc.id];
                    final submittedDay = submission?.submittedAt;
                    final taskInRange =
                        day != null &&
                        !day.isBefore(earliest) &&
                        !day.isAfter(todayOnly);
                    final submissionInRange =
                        submittedDay != null &&
                        !submittedDay.isBefore(earliest) &&
                        !submittedDay.isAfter(DateTime.now());
                    return taskInRange || submissionInRange;
                  }).toList();
                  docs.sort((a, b) {
                    final aSubmission = updatesByTask[a.id]?.submittedAt;
                    final bSubmission = updatesByTask[b.id]?.submittedAt;
                    final aDay =
                        aSubmission ?? _taskDay(a.data()) ?? DateTime(1970);
                    final bDay =
                        bSubmission ?? _taskDay(b.data()) ?? DateTime(1970);
                    final byDay = bDay.compareTo(aDay);
                    if (byDay != 0) return byDay;
                    return _taskTime(b.data()).compareTo(_taskTime(a.data()));
                  });
                  final flags = docs
                      .map(
                        (doc) =>
                            updatesByTask[doc.id] ??
                            const _ActivitySubmissionInfo(
                              submitted: false,
                              submittedOverdue: false,
                            ),
                      )
                      .toList();
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegmentedButton<int>(
                              showSelectedIcon: false,
                              style: ButtonStyle(
                                shape: WidgetStateProperty.all(
                                  const StadiumBorder(),
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.symmetric(horizontal: 4),
                                ),
                                textStyle: WidgetStateProperty.all(
                                  const TextStyle(fontSize: 12),
                                ),
                              ),
                              segments: const [
                                ButtonSegment(
                                  value: 1,
                                  label: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '1 mo',
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                  tooltip: '1 month',
                                ),
                                ButtonSegment(
                                  value: 3,
                                  label: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '3 mo',
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                  tooltip: '3 months',
                                ),
                                ButtonSegment(
                                  value: 6,
                                  label: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      '6 mo',
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                  tooltip: '6 months',
                                ),
                              ],
                              selected: {_months},
                              onSelectionChanged: (selection) {
                                setState(() => _months = selection.first);
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _ActivitySummaryCard(
                                    label: 'Tasks & submissions',
                                    count: docs.length,
                                    icon: Icons.assignment_outlined,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _ActivitySummaryCard(
                                    label: 'Submitted',
                                    count: flags
                                        .where((value) => value.submitted)
                                        .length,
                                    icon: Icons.task_alt,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _ActivitySummaryCard(
                                    label: 'Net credits',
                                    count: awardsSnapshot.hasData
                                        ? periodCredits
                                        : null,
                                    icon: Icons.workspace_premium_outlined,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (docs.isEmpty)
                        const Expanded(
                          child: Center(
                            child: Text('No assigned tasks in this period.'),
                          ),
                        )
                      else
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final task = doc.data();
                              final submission = flags[index];
                              final day =
                                  submission.submittedAt ??
                                  _taskDay(task) ??
                                  DateTime(1970);
                              final submitted = submission.submitted;
                              final hasAward = positiveAwardTasks.contains(
                                doc.id,
                              );
                              final penalty = penaltyByTask[doc.id] ?? 0;
                              final taskCredits = creditsByTask[doc.id] ?? 0;
                              final approvalLabel = hasAward
                                  ? 'Approved'
                                  : submitted
                                  ? 'Awaiting approval'
                                  : penalty < 0
                                  ? 'Penalty applied'
                                  : 'Pending';
                              final statusTextStyle = Theme.of(context)
                                  .textTheme
                                  .bodyMedium;
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => TaskDetailsPage(
                                        taskId: doc.id,
                                        currentUserUid: widget.currentUserUid,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Use the full card width so the time's right edge
                                        // lines up with the approval label below it.
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                (task['title'] ??
                                                        'Assigned task')
                                                    .toString(),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 155,
                                              ),
                                              child: Text(
                                                _taskTime(task),
                                                textAlign: TextAlign.right,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _prettyDate(day),
                                          style: statusTextStyle,
                                        ),
                                        if (submission.submittedOverdue) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Overdue · Submitted${submission.submittedAt == null ? '' : ' ${_prettyDate(submission.submittedAt!)}'}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: const Color(
                                                    0xFFD97706,
                                                  ),
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        Text(
                                          'Shared status: ${task['status'] ?? 'Pending'}',
                                          style: statusTextStyle,
                                        ),
                                        Text(
                                          submitted
                                              ? 'Your work update: ${switch (submission.reviewStatus) {
                                                  'accepted' => 'Evidence accepted',
                                                  'pending' => 'Evidence pending review',
                                                  'rework_requested' => 'Rework requested',
                                                  'location_mismatch' => 'Location clarification requested',
                                                  _ => 'Submitted',
                                                }}'
                                              : 'Your work update: Pending',
                                          style: statusTextStyle?.copyWith(
                                            color:
                                                submission.reviewStatus ==
                                                    'accepted'
                                                ? const Color(0xFF059669)
                                                : null,
                                            fontWeight:
                                                submission.reviewStatus ==
                                                    'accepted'
                                                ? FontWeight.w700
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  if (hasAward)
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .workspace_premium_outlined,
                                                          size: 18,
                                                          color: const Color(
                                                            0xFFF59E0B,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 5,
                                                        ),
                                                        Text(
                                                          '+${creditsByTask[doc.id] != null && penalty < 0 ? taskCredits - penalty : taskCredits} credits',
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontSize: 15,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  if (penalty < 0)
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.trending_down,
                                                          size: 18,
                                                          color: const Color(
                                                            0xFFB91C1C,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 5,
                                                        ),
                                                        Text(
                                                          '$penalty credits',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 15,
                                                            color: const Color(
                                                              0xFFB91C1C,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  if (!hasAward && penalty == 0)
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .schedule_outlined,
                                                          size: 18,
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                        const SizedBox(
                                                          width: 5,
                                                        ),
                                                        const Text(
                                                          '0 credits',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 15,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              approvalLabel,
                                              textAlign: TextAlign.right,
                                              style: TextStyle(
                                                color: hasAward
                                                    ? const Color(0xFF059669)
                                                    : penalty < 0
                                                    ? const Color(0xFFB91C1C)
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ActivitySummaryCard extends StatelessWidget {
  const _ActivitySummaryCard({
    required this.label,
    required this.count,
    required this.icon,
  });
  final String label;
  final int? count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              count?.toString() ?? '...',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
