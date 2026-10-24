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
  });

  final bool submitted;
  final bool submittedOverdue;
  final DateTime? submittedAt;
}

class _CrewActivityPageState extends State<CrewActivityPage> {
  int _months = 1;
  late final Stream<List<FieldTaskRecord>> _assignedTasks;
  Future<List<_ActivitySubmissionInfo>>? _submissionFuture;
  String? _submissionKey;

  @override
  void initState() {
    super.initState();
    _assignedTasks = fieldTasksStream();
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

  Future<List<_ActivitySubmissionInfo>> _loadSubmissions(
    List<FieldTaskRecord> docs,
  ) async {
    return Future.wait(
      docs.map((doc) async {
        final result = await fieldBackend
            .from('field_work_updates')
            .select('submitted_at,submitted_overdue')
            .eq('task_id', doc.id)
            .eq('submitted_by_uid', widget.currentUserUid);
        final overdueDocs = result
            .where((update) => update['submitted_overdue'] == true)
            .toList();
        final chosen = overdueDocs.isNotEmpty
            ? overdueDocs.first
            : (result.isNotEmpty ? result.first : null);
        final submittedAtRaw = chosen?['submitted_at'];
        return _ActivitySubmissionInfo(
          submitted: result.isNotEmpty,
          submittedOverdue: overdueDocs.isNotEmpty,
          submittedAt: fieldDateTime(submittedAtRaw),
        );
      }),
    );
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
              final docs = snapshot.data!.where((doc) {
                final day = _taskDay(doc.data());
                return day != null &&
                    !day.isBefore(earliest) &&
                    !day.isAfter(todayOnly);
              }).toList();
              docs.sort((a, b) {
                final byDay = _taskDay(b.data())!
                    .compareTo(_taskDay(a.data())!);
                if (byDay != 0) return byDay;
                return _taskTime(b.data()).compareTo(_taskTime(a.data()));
              });

              // Reuse the result while rebuilding; reload when the task set or
              // filter changes. Opening this page again also makes a fresh query.
              final key = '$_months:${docs.map((d) => d.id).join('|')}';
              if (_submissionFuture == null || _submissionKey != key) {
                _submissionKey = key;
                _submissionFuture = _loadSubmissions(docs);
              }
              return FutureBuilder<List<_ActivitySubmissionInfo>>(
                future: _submissionFuture,
                builder: (context, updates) {
                  if (updates.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Unable to read personal work updates: '
                          '${updates.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final flags = updates.data;
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
                                    label: 'Tasks assigned',
                                    count: docs.length,
                                    icon: Icons.assignment_outlined,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _ActivitySummaryCard(
                                    label: 'Submitted',
                                    count: flags == null
                                        ? null
                                        : flags
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
                      if (flags == null)
                        const Expanded(
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (docs.isEmpty)
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
                              final day = _taskDay(task)!;
                              final submission = flags[index];
                              final submitted = submission.submitted;
                              final isPastDate = DateTime(
                                day.year,
                                day.month,
                                day.day,
                              ).isBefore(todayOnly);
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
                                        // Omit the redundant personal-update status for
                                        // past dates. On today's task use the same font as
                                        // the shared status for consistency.
                                        if (!isPastDate)
                                          Text(
                                            submitted
                                                ? 'Your work update: Submitted'
                                                : 'Your work update: Pending',
                                            style: statusTextStyle,
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
