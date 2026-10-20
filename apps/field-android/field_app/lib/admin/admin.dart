part of '../main.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key, required this.user});
  final User user;

  Future<void> _logout() => FirebaseAuth.instance.signOut();

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
                    const Icon(Icons.admin_panel_settings_outlined,
                        size: 72, color: const Color(0xFF0F766E)),
                    const SizedBox(height: 16),
                    const Text('Administrator Dashboard',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'You are signed in with an administrator account.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) =>
                              AdminCreditReviewPage(adminUid: user.uid))),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Review Work & Award Credits'),
                    ),
                    const SizedBox(height: 16),
                    const ListTile(
                      leading: Icon(Icons.person_add_alt_1),
                      title: Text('Add crew member'),
                      subtitle: Text(
                        'Account creation needs a trusted backend. It is not enabled yet, so this screen cannot create accounts securely.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Next step: connect a secure free-tier backend before enabling account creation. Do not place service-account credentials or admin secrets in this Flutter app.',
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
  const AdminCreditReviewPage({super.key, required this.adminUid});
  final String adminUid;

  Future<void> _approve(BuildContext context, String taskId,
      String uid, String taskTitle) async {
    final input = TextEditingController(text: '10');
    final amount = await showDialog<int>(context: context, builder: (dialogContext) =>
        AlertDialog(title: const Text('Approve work & grant credits'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(taskTitle), const SizedBox(height: 12),
            TextField(controller: input, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Credits to grant (1–1000)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              final points = int.tryParse(input.text.trim());
              if (points == null || points < 1 || points > 1000) return;
              Navigator.pop(dialogContext, points);
            }, child: const Text('Approve')),
          ],
        ));
    input.dispose();
    if (amount == null || !context.mounted) return;
    try {
      final db = FirebaseFirestore.instance;
      final taskRef = db.collection('tasks').doc(taskId);
      final awardRef = db.collection('users').doc(uid).collection('creditAwards').doc(taskId);
      await db.runTransaction((tx) async {
        final task = await tx.get(taskRef);
        final prior = await tx.get(awardRef);
        if (prior.exists) throw StateError('Credits already granted for this task and member.');
        final assigned = task.data()?['assignedToUid'];
        if (!task.exists || assigned is! List || !assigned.contains(uid)) {
          throw StateError('This crew member is not assigned to the task.');
        }
        // The review screen also checks submission evidence before enabling approval.
        tx.set(awardRef, {
          'taskId': taskId,
          'taskTitle': taskTitle,
          'crewUid': uid,
          'credits': amount,
          'approvedByUid': adminUid,
          'approvedAt': FieldValue.serverTimestamp(),
        });
      });
      if (context.mounted) showAppMessage(context, '$amount credits awarded.');
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Could not approve: $e');
    }
  }

  Future<void> _applyOverdueDeductions(BuildContext context) async {
    try {
      final count = await processOverdueDeductionsForAdmin(adminUid);
      if (context.mounted) {
        showAppMessage(context, count == 0
            ? 'No new overdue deductions were needed.'
            : 'Applied $count overdue daily deduction(s).');
      }
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Could not process overdue deductions: $e');
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
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('tasks').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final task = snapshot.data!.docs[index];
            return Card(child: ExpansionTile(
              title: Text((task.data()['title'] ?? 'Task').toString()),
              subtitle: Text((task.data()['dateKey'] ?? '').toString()),
              children: [
                _DailyOverdueRateEditor(
                  taskReference: task.reference,
                  initialRate: task.data()['dailyOverdueDeduction'] is int
                      ? task.data()['dailyOverdueDeduction'] as int
                      : 0,
                ),
                for (final uid in (task.data()['assignedToUid'] is List
                    ? (task.data()['assignedToUid'] as List).whereType<String>()
                    : <String>[]))
                  FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    future: task.reference.collection('workUpdates')
                        .where('submittedByUid', isEqualTo: uid).get(),
                    builder: (context, proof) {
                      if (!proof.hasData) return const ListTile(title: Text('Checking evidence...'));
                      final hasEvidence = proof.data!.docs.isNotEmpty;
                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance.collection('users').doc(uid)
                            .collection('creditAwards').doc(task.id).snapshots(),
                        builder: (context, award) {
                          final granted = award.data?.exists ?? false;
                          final member = (task.data()['crewMembers'] is List
                              ? (task.data()['crewMembers'] as List).whereType<Map>().toList()
                              : <Map>[]);
                          final matches = member.where((m) => m['uid'] == uid);
                          final name = matches.isEmpty ? uid :
                          (matches.first['name'] ?? matches.first['fullName'] ?? uid).toString();
                          return ListTile(
                            title: Text(name),
                            subtitle: Text(granted ? 'Credits approved' :
                            hasEvidence ? '${proof.data!.docs.length} work photo(s) submitted' :
                            'No work submitted'),
                            trailing: granted ? const Icon(Icons.check_circle, color: const Color(0xFF059669)) :
                            TextButton(onPressed: hasEvidence ?
                                () => _approve(context, task.id, uid,
                                (task.data()['title'] ?? 'Task').toString()) : null,
                                child: const Text('Award credits')),
                          );
                        },
                      );
                    },
                  ),
              ],
            ));
          },
        );
      },
    ),
  );
}

class _DailyOverdueRateEditor extends StatefulWidget {
  const _DailyOverdueRateEditor({
    required this.taskReference,
    required this.initialRate,
  });

  final DocumentReference<Map<String, dynamic>> taskReference;
  final int initialRate;

  @override
  State<_DailyOverdueRateEditor> createState() => _DailyOverdueRateEditorState();
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
      showAppMessage(context, 'Enter a daily deduction from 0 to 1000 credits.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.taskReference.update({'dailyOverdueDeduction': rate});
      if (mounted) showAppMessage(context, rate == 0
          ? 'Daily overdue deduction disabled for this task.'
          : 'Daily overdue deduction set to $rate credits.');
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save daily deduction: $e');
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
        const Text('Daily overdue deduction', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Set 0 to disable. The admin action applies each missing overdue day once.'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Credits deducted per overdue day',
              prefixIcon: Icon(Icons.trending_down),
            ),
          )),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _saving ? null : _saveRate,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save rate'),
          ),
        ]),
      ],
    ),
  );
}
