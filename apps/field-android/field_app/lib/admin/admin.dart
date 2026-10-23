part of '../main.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  Future<void> _logout() => fieldBackend.auth.signOut();

  Future<void> _createCrewAccount(BuildContext context) async {
    final municipalId = TextEditingController();
    final fullName = TextEditingController();
    final password = TextEditingController();
    String? validationError;
    final account = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create crew account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: municipalId,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Municipal ID'),
              ),
              TextField(
                controller: fullName,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              TextField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Temporary password (8+ characters)',
                ),
              ),
              if (validationError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final id = municipalId.text.trim().toUpperCase();
                final name = fullName.text.trim();
                final secret = password.text;
                if (!RegExp(r'^[A-Z0-9-]{3,30}$').hasMatch(id)) {
                  setDialogState(
                    () => validationError = 'Enter a valid Municipal ID.',
                  );
                } else if (name.length < 2 || name.length > 100) {
                  setDialogState(
                    () => validationError = 'Enter a valid full name.',
                  );
                } else if (secret.length < 8) {
                  setDialogState(
                    () => validationError =
                        'Password must be at least 8 characters.',
                  );
                } else {
                  Navigator.pop(dialogContext, {
                    'municipalId': id,
                    'fullName': name,
                    'password': secret,
                  });
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    municipalId.dispose();
    fullName.dispose();
    password.dispose();
    if (account == null || !context.mounted) return;

    try {
      final result = await fieldBackend.functions.invoke(
        'create-crew-account',
        body: account,
      );
      if (result.status < 200 || result.status >= 300) {
        throw StateError('Crew account creation failed: ${result.data}');
      }
      if (context.mounted) {
        showAppMessage(
          context,
          'Crew account ${account['municipalId']} created successfully.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        showAppMessage(context, 'Could not create crew account: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Municipal Board Admin'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 72,
                      color: const Color(0xFF0F766E),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Administrator Dashboard',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You are signed in with an administrator account.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const AdminCreditReviewPage(),
                        ),
                      ),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Review Work & Award Credits'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => _createCrewAccount(context),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Add crew member'),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('LOG OUT'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Admin-only review UI. Server rules, not the widget, authorize awards.
class AdminCreditReviewPage extends StatelessWidget {
  const AdminCreditReviewPage({super.key});

  Future<void> _approve(
    BuildContext context,
    String taskId,
    String uid,
    String taskTitle,
  ) async {
    final input = TextEditingController(text: '10');
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve work & grant credits'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(taskTitle),
            const SizedBox(height: 12),
            TextField(
              controller: input,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Credits to grant (1–1000)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final points = int.tryParse(input.text.trim());
              if (points == null || points < 1 || points > 1000) return;
              Navigator.pop(dialogContext, points);
            },
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    input.dispose();
    if (amount == null || !context.mounted) return;
    try {
      await fieldBackend.rpc(
        'grant_field_credits',
        params: {'p_task_id': taskId, 'p_crew_uid': uid, 'p_credits': amount},
      );
      if (context.mounted) showAppMessage(context, '$amount credits awarded.');
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Could not approve: $e');
    }
  }

  Future<void> _applyOverdueDeductions(BuildContext context) async {
    try {
      final count = await processOverdueDeductionsForAdmin();
      if (context.mounted) {
        showAppMessage(
          context,
          count == 0
              ? 'No new overdue deductions were needed.'
              : 'Applied $count overdue daily deduction(s).',
        );
      }
    } catch (e) {
      if (context.mounted)
        showAppMessage(context, 'Could not process overdue deductions: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Review Work & Credits'),
      actions: [
        IconButton(
          tooltip: 'Process overdue deductions',
          onPressed: () => _applyOverdueDeductions(context),
          icon: const Icon(Icons.trending_down),
        ),
      ],
    ),
    body: StreamBuilder<List<Map<String, dynamic>>>(
      stream: fieldTasksStream(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        return ListView.builder(
          itemCount: snapshot.data!.length,
          itemBuilder: (context, index) {
            final task = snapshot.data![index];
            return Card(
              child: ExpansionTile(
                title: Text((task['title'] ?? 'Task').toString()),
                subtitle: Text((task['dateKey'] ?? '').toString()),
                children: [
                  _DailyOverdueRateEditor(
                    taskId: task['id'] as String,
                    initialRate: task['dailyOverdueDeduction'] is int
                        ? task['dailyOverdueDeduction'] as int
                        : 0,
                  ),
                  for (final uid
                      in (task['assignedToUid'] is List
                          ? (task['assignedToUid'] as List).whereType<String>()
                          : <String>[]))
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: fieldBackend
                          .from('field_work_updates')
                          .select()
                          .eq('task_id', task['id'])
                          .eq('submitted_by_uid', uid),
                      builder: (context, proof) {
                        if (proof.hasError) {
                          return ListTile(
                            title: Text(uid),
                            subtitle: Text(
                              'Could not load work evidence: ${proof.error}',
                            ),
                          );
                        }
                        if (!proof.hasData)
                          return const ListTile(
                            title: Text('Checking evidence...'),
                          );
                        final hasEvidence = proof.data!.isNotEmpty;
                        final member = (task['crewMembers'] is List
                            ? (task['crewMembers'] as List)
                                  .whereType<Map>()
                                  .toList()
                            : <Map>[]);
                        final matches = member.where((m) => m['uid'] == uid);
                        final name = matches.isEmpty
                            ? uid
                            : (matches.first['name'] ??
                                      matches.first['fullName'] ??
                                      uid)
                                  .toString();
                        return StreamBuilder<List<Map<String, dynamic>>>(
                          stream: fieldCreditsStream(),
                          builder: (context, award) {
                            if (award.hasError) {
                              return ListTile(
                                title: Text(name),
                                subtitle: Text(
                                  'Could not load credit approvals: ${award.error}',
                                ),
                              );
                            }
                            final grants = (award.data ?? [])
                                .where(
                                  (row) =>
                                      row['taskId'] == task['id'] &&
                                      row['crewUid'] == uid,
                                )
                                .toList();
                            final granted = grants.isNotEmpty;
                            return ListTile(
                              title: Text(name),
                              subtitle: Text(
                                granted
                                    ? 'Credits approved'
                                    : hasEvidence
                                    ? '${proof.data!.length} work photo(s) submitted'
                                    : 'No work submitted',
                              ),
                              trailing: granted
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: const Color(0xFF059669),
                                    )
                                  : TextButton(
                                      onPressed: hasEvidence
                                          ? () => _approve(
                                              context,
                                              task['id'] as String,
                                              uid,
                                              (task['title'] ?? 'Task')
                                                  .toString(),
                                            )
                                          : null,
                                      child: const Text('Award credits'),
                                    ),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}

class _DailyOverdueRateEditor extends StatefulWidget {
  const _DailyOverdueRateEditor({
    required this.taskId,
    required this.initialRate,
  });

  final String taskId;
  final int initialRate;

  @override
  State<_DailyOverdueRateEditor> createState() =>
      _DailyOverdueRateEditorState();
}

class _DailyOverdueRateEditorState extends State<_DailyOverdueRateEditor> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialRate.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveRate() async {
    final rate = int.tryParse(_controller.text.trim());
    if (rate == null || rate < 0 || rate > 1000) {
      showAppMessage(
        context,
        'Enter a daily deduction from 0 to 1000 credits.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await fieldBackend.rpc(
        'set_field_task_overdue_rate',
        params: {'p_task_id': widget.taskId, 'p_daily_rate': rate},
      );
      if (mounted)
        showAppMessage(
          context,
          rate == 0
              ? 'Daily overdue deduction disabled for this task.'
              : 'Daily overdue deduction set to $rate credits.',
        );
    } catch (e) {
      if (mounted)
        showAppMessage(context, 'Could not save daily deduction: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Daily overdue deduction',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Set 0 to disable. The admin action applies each missing overdue day once.',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Credits deducted per overdue day',
                  prefixIcon: Icon(Icons.trending_down),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _saveRate,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save rate'),
            ),
          ],
        ),
      ],
    ),
  );
}
