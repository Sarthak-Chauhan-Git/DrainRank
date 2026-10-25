part of '../main.dart';

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({
    required this.label,
    required this.value,
    required this.onCopy,
  });

  final String label;
  final String value;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF0FDFA),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFB9DED3)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              SelectableText(
                value,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Copy $label',
          onPressed: onCopy,
          icon: const Icon(Icons.copy_rounded),
        ),
      ],
    ),
  );
}

class _CreateCrewAccountDialog extends StatefulWidget {
  const _CreateCrewAccountDialog();

  @override
  State<_CreateCrewAccountDialog> createState() =>
      _CreateCrewAccountDialogState();
}

class _CreateCrewAccountDialogState extends State<_CreateCrewAccountDialog> {
  final _municipalIdController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _validationError;
  bool _hidePassword = true;

  @override
  void dispose() {
    _municipalIdController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _createAccount() {
    final id = _municipalIdController.text.trim().toUpperCase();
    final name = _fullNameController.text.trim();
    final secret = _passwordController.text;
    if (!RegExp(r'^[A-Z0-9-]{3,30}$').hasMatch(id)) {
      setState(
        () => _validationError =
            'Use 3–30 letters, numbers, or hyphens for the ID.',
      );
    } else if (name.length < 2 || name.length > 100) {
      setState(() => _validationError = 'Enter a valid full name.');
    } else if (secret.length < 8) {
      setState(
        () => _validationError = 'Password must be at least 8 characters.',
      );
    } else {
      Navigator.pop(context, {
        'municipalId': id,
        'fullName': name,
        'password': secret,
      });
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F8F1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.person_add_alt_1_rounded,
                color: Color(0xFF0F766E),
                size: 28,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Add crew member',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Create a secure sign-in for a municipal field worker. '
              'Their credentials will be shown once after creation.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _municipalIdController,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Municipal ID',
                hintText: 'For example, CREW-1024',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fullNameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _hidePassword,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _createAccount(),
              decoration: InputDecoration(
                labelText: 'Temporary password',
                helperText: 'Must be at least 8 characters.',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _hidePassword ? 'Show password' : 'Hide password',
                  onPressed: () =>
                      setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(
                    _hidePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 12),
              Text(
                _validationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _createAccount,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Create account'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  Future<void> _logout() => fieldBackend.auth.signOut();

  Future<void> _createCrewAccount(BuildContext context) async {
    final account = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _CreateCrewAccountDialog(),
    );
    if (account == null || !context.mounted) return;

    try {
      final result = await fieldBackend.functions.invoke(
        'create-crew-account',
        body: account,
      );
      if (result.status < 200 || result.status >= 300) {
        final details = result.data is Map
            ? (result.data as Map)['error']?.toString()
            : null;
        throw StateError(
          details ?? 'Crew account creation failed (HTTP ${result.status}).',
        );
      }
      if (result.data is! Map || (result.data as Map)['userId'] is! String) {
        throw StateError(
          'The server response was incomplete. Check the crew list before retrying.',
        );
      }
      if (context.mounted) {
        await _showCreatedCrewCredentials(context, account);
      }
    } on FunctionException catch (error) {
      if (context.mounted) {
        showAppMessage(context, _crewProvisioningError(error));
      }
    } catch (error) {
      if (context.mounted) {
        showAppMessage(context, 'Could not create crew account: $error');
      }
    }
  }

  String _crewProvisioningError(FunctionException error) {
    final details = error.details;
    final serverMessage = details is Map
        ? details['error']?.toString()
        : details?.toString();
    if (error.status == 0) {
      return 'Could not reach the crew account service. Check the network and try again.';
    }
    if (error.status == 404) {
      return 'Crew account service was not found. Deploy create-crew-account to this Supabase project.';
    }
    return 'Could not create crew account (HTTP ${error.status}): '
        '${serverMessage?.isNotEmpty == true ? serverMessage : error.reasonPhrase ?? 'Request failed.'}';
  }

  Future<void> _showCreatedCrewCredentials(
    BuildContext context,
    Map<String, String> account,
  ) async {
    final municipalId = account['municipalId']!;
    final password = account['password']!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.verified_user_outlined,
          color: Color(0xFF0F766E),
          size: 36,
        ),
        title: const Text('Crew account created'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share these sign-in details securely with the crew member. '
                'The password will not be available here again.',
              ),
              const SizedBox(height: 18),
              _CredentialRow(
                label: 'Municipal ID',
                value: municipalId,
                onCopy: () =>
                    _copyCredential(context, 'Municipal ID', municipalId),
              ),
              const SizedBox(height: 12),
              _CredentialRow(
                label: 'Temporary password',
                value: password,
                onCopy: () =>
                    _copyCredential(context, 'Temporary password', password),
              ),
              const SizedBox(height: 12),
              Text(
                'Store the temporary password securely. It cannot be retrieved '
                'from this screen after you close it.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCredential(
    BuildContext context,
    String label,
    String value,
  ) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) showAppMessage(context, '$label copied.');
    } catch (error) {
      if (context.mounted) {
        showAppMessage(context, 'Could not copy $label: $error');
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
      stream: fieldTasksStream().map(
        (tasks) => tasks.map((task) => task.data()).toList(),
      ),
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
