part of '../main.dart';

class CrewHomePage extends StatefulWidget {
  const CrewHomePage({
    super.key,
    required this.user,
    required this.profile,
    required this.onLogout,
  });

  final User user;
  final Map<String, dynamic> profile;
  final Future<void> Function() onLogout;

  @override
  State<CrewHomePage> createState() => _CrewHomePageState();
}

class _CrewHomePageState extends State<CrewHomePage> {
  int _selectedSection = 0;
  int _selectedRange = 1;
  bool _debugModeEnabled = false;
  late Stream<List<FieldTaskRecord>> _tasksStream;
  StreamSubscription<List<Map<String, dynamic>>>? _workUpdatesSubscription;
  Map<String, Map<String, dynamic>> _workUpdatesByTask = {};
  bool _loadingWorkUpdates = true;
  String? _workUpdatesError;
  static const _avatarColors = [
    Color(0xFF0F766E),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFBE123C),
    Color(0xFFB45309),
    Color(0xFF047857),
  ];

  @override
  void initState() {
    super.initState();
    _openTaskStream();
    _openWorkUpdatesStream();
  }

  void _openTaskStream() {
    _tasksStream = fieldTasksStream();
  }

  void _openWorkUpdatesStream() {
    final previousSubscription = _workUpdatesSubscription;
    if (previousSubscription != null) {
      unawaited(previousSubscription.cancel());
    }
    _loadingWorkUpdates = true;
    _workUpdatesError = null;
    _workUpdatesSubscription = fieldWorkUpdatesStream().listen(
      (updates) {
        if (!mounted) return;
        setState(() {
          _workUpdatesByTask = {
            for (final update in updates)
              if (update['submittedByUid'] == widget.user.uid &&
                  update['taskId'] is String)
                update['taskId'] as String: update,
          };
          _loadingWorkUpdates = false;
          _workUpdatesError = null;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Work evidence loading error: $error\n$stackTrace');
        if (!mounted) return;
        setState(() {
          _loadingWorkUpdates = false;
          _workUpdatesError = 'Unable to load submitted work evidence.';
        });
      },
    );
  }

  @override
  void dispose() {
    final subscription = _workUpdatesSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  DateTime _dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  DateTime? _taskDisplayDate(FieldTaskRecord task) {
    final update = _workUpdatesByTask[task.id];
    if (_selectedRange == 0 &&
        update != null &&
        update['review_status'] != 'rework_requested') {
      final submittedAt = fieldDateTime(update['submittedAt']);
      if (submittedAt != null) return _dayOnly(submittedAt.toLocal());
    }
    return _parseTaskDate(task.data()['dateKey']);
  }

  String get _crewName {
    final name =
        (widget.profile['fullName'] ??
                widget.profile['name'] ??
                widget.user.displayName ??
                '')
            .toString()
            .trim();
    return name.isNotEmpty
        ? name
        : (widget.user.email?.split('@').first ?? 'Crew Member');
  }

  String get _municipalId =>
      (widget.profile['municipalId'] ?? '').toString().trim();

  String get _crewRole {
    final role = (widget.profile['role'] ?? '').toString().trim();
    if (role.isEmpty || role.toLowerCase() == 'crew') return 'Crew Member';
    return role;
  }

  String get _initials {
    final parts = _crewName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'C';
    return parts.length == 1
        ? parts.first.substring(0, 1).toUpperCase()
        : '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
              .toUpperCase();
  }

  Color get _avatarColor {
    final seed = (_municipalId.isNotEmpty ? _municipalId : _crewName).codeUnits
        .fold<int>(0, (value, unit) => (value * 31 + unit) & 0x7fffffff);
    return _avatarColors[seed % _avatarColors.length];
  }

  List<DateTime> _visibleDays() {
    final today = _dayOnly(DateTime.now());
    if (_selectedRange == 1) return [];
    return List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
  }

  // Handles both '08:00 AM' and '13:00' time strings for chronological sorting.
  int _timeInMinutes(String? raw) {
    if (raw == null) return 9999;
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) return 9999;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)?.toUpperCase();
    if (minute > 59 ||
        hour > (period == null ? 23 : 12) ||
        hour == 0 && period != null) {
      return 9999;
    }
    if (period != null) hour = (hour % 12) + (period == 'PM' ? 12 : 0);
    return hour * 60 + minute;
  }

  Future<void> _refreshTasks() async {
    try {
      await Future.wait([
        fieldBackend.from('field_tasks').select('id').limit(1),
        fieldBackend
            .from('field_work_updates')
            .select('id')
            .eq('submitted_by_uid', widget.user.uid)
            .limit(1),
        fieldBackend
            .from('credit_awards')
            .select('id')
            .eq('user_id', widget.user.uid)
            .limit(1),
        fieldBackend
            .from('direct_cleaning_report_credits')
            .select('report_id')
            .eq('user_id', widget.user.uid)
            .limit(1),
      ]);
      if (!mounted) return;
      setState(() {
        _openTaskStream();
        _openWorkUpdatesStream();
      });
    } catch (error) {
      if (mounted) {
        showAppMessage(context, 'Could not refresh tasks and credits: $error');
      }
    }
  }

  void _showDetails(String title, Widget content) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(sheetContext).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              content,
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileDetails() {
    return CrewIdentityCard(
      name: _crewName,
      role: _crewRole,
      municipalId: _municipalId,
      email: widget.user.email ?? '',
      initials: _initials,
      avatarColor: _avatarColor,
    );
  }

  Future<void> _openLeaveRequest() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RequestLeavePage(
          currentUserUid: widget.user.uid,
          crewName: _crewName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleDays = _visibleDays();
    final visibleKeys = visibleDays.map(_dateKey).toSet();
    final heading = switch (_selectedRange) {
      0 => 'Last week',
      _ => 'Active tasks',
    };

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        centerTitle: false,
        toolbarHeight: 72,
        titleSpacing: 16,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.asset(
                'assets/logo.png',
                width: 44,
                height: 44,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pravah Saarthi',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: -0.3,
                    height: 1.05,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'FIELD TEAM',
                  style: TextStyle(
                    color: Color(0xFF99F6E4),
                    fontSize: 9,
                    letterSpacing: 1.05,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'पहचान से समाधान तक।',
                  style: TextStyle(
                    color: Color(0xFFCBD5E1),
                    fontSize: 10,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Your profile',
            onPressed: () => setState(() => _selectedSection = 3),
            icon: CircleAvatar(
              radius: 17,
              backgroundColor: _avatarColor,
              child: Text(
                _initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: _CrewBottomNavigation(
        selectedIndex: _selectedSection,
        onSelected: (index) => setState(() => _selectedSection = index),
      ),
      body: IndexedStack(
        index: _selectedSection,
        children: [
          StreamBuilder<List<FieldTaskRecord>>(
            stream: _tasksStream,
            builder: (context, snapshot) {
              if (_loadingWorkUpdates) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_workUpdatesError != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 44),
                        const SizedBox(height: 12),
                        const Text('Unable to load submitted work evidence'),
                        const SizedBox(height: 8),
                        const Text(
                          'Active tasks cannot be updated until evidence status is available.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _refreshTasks,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                debugPrint('Task loading error: ${snapshot.error}');
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off_outlined, size: 44),
                        const SizedBox(height: 12),
                        const Text('Unable to load assigned tasks'),
                        const SizedBox(height: 8),
                        Text(
                          'Check your internet connection and confirm this crew account '
                          'is assigned to the task in Supabase.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _refreshTasks,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final allAssignedTasks = snapshot.data ?? [];
              final filtered = allAssignedTasks.where((doc) {
                final task = doc.data();
                final update = _workUpdatesByTask[doc.id];
                final day = _taskDisplayDate(doc);
                if (day == null) return false;
                if (_selectedRange == 0) {
                  return visibleKeys.contains(_dateKey(day));
                }
                final status = (task['status'] ?? 'Pending')
                    .toString()
                    .toLowerCase();
                return status != 'completed' &&
                    status != 'cancelled' &&
                    status != 'canceled' &&
                    (update == null ||
                        update['review_status'] == 'rework_requested' ||
                        update['review_status'] == 'location_mismatch');
              }).toList();
              filtered.sort((a, b) {
                final dayA = _taskDisplayDate(a)!;
                final dayB = _taskDisplayDate(b)!;
                final byDay = dayA.compareTo(dayB);
                if (byDay != 0) return byDay;
                return _timeInMinutes(
                  a.data()['startTime']?.toString(),
                ).compareTo(_timeInMinutes(b.data()['startTime']?.toString()));
              });
              final byDate = <String, List<FieldTaskRecord>>{};
              for (final doc in filtered) {
                final dateKey = _dateKey(_taskDisplayDate(doc)!);
                byDate.putIfAbsent(dateKey, () => []).add(doc);
              }
              for (final tasks in byDate.values) {
                tasks.sort(
                  (a, b) => _timeInMinutes(a.data()['startTime']?.toString())
                      .compareTo(
                        _timeInMinutes(b.data()['startTime']?.toString()),
                      ),
                );
              }

              final displayDays =
                  _selectedRange == 0
                        ? visibleDays
                        : byDate.keys
                              .map(_parseTaskDate)
                              .whereType<DateTime>()
                              .toList()
                    ..sort((a, b) => a.compareTo(b));

              return RefreshIndicator(
                onRefresh: _refreshTasks,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                  children: [
                    Text(
                      'Welcome back,',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      _crewName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7E6),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                Icons.workspace_premium_outlined,
                                color: Color(0xFFB7791F),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Your contribution',
                                    style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  CrewCredits(
                                    uid: widget.user.uid,
                                    compact: true,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'My schedule',
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    _TaskRangeSelector(
                      selectedIndex: _selectedRange,
                      onSelected: (index) =>
                          setState(() => _selectedRange = index),
                    ),
                    const SizedBox(height: 16),
                    if (_selectedRange == 1)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Assigned work awaiting your evidence or returned for rework.',
                        ),
                      ),
                    Text(
                      heading,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    if (_selectedRange == 0)
                      Text(
                        '${_prettyDate(visibleDays.first)} – ${_prettyDate(visibleDays.last)}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    const SizedBox(height: 12),
                    if (filtered.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            children: [
                              const Icon(Icons.event_busy_outlined, size: 42),
                              const SizedBox(height: 12),
                              Text(
                                _selectedRange == 0
                                    ? 'No submitted or assigned tasks in the last 7 days.'
                                    : 'No active assigned tasks.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _selectedRange == 0
                                    ? 'Recent submissions and assignments will appear here automatically.'
                                    : 'New assignments and their deadlines will appear here.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    for (final date in displayDays)
                      if (byDate[_dateKey(date)]?.isNotEmpty == true) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                          child: Text(
                            _prettyDate(date),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        for (var i = 0; i < byDate[_dateKey(date)]!.length; i++)
                          _DrainTaskCard(
                            data: byDate[_dateKey(date)]![i].data(),
                            number: i + 1,
                            taskId: byDate[_dateKey(date)]![i].id,
                            currentUserUid: widget.user.uid,
                            showCredits: true,
                            evidenceStatus:
                                _workUpdatesByTask[byDate[_dateKey(date)]![i]
                                        .id]?['review_status']
                                    as String?,
                            isOverdue:
                                _selectedRange == 1 &&
                                date.isBefore(_todayOnly()),
                            showDeadline: _selectedRange == 1,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => TaskDetailsPage(
                                  taskId: byDate[_dateKey(date)]![i].id,
                                  currentUserUid: widget.user.uid,
                                ),
                              ),
                            ),
                          ),
                      ],
                  ],
                ),
              );
            },
          ),
          DirectCleaningReportPage(user: widget.user),
          CrewActivityPage(currentUserUid: widget.user.uid, embedded: true),
          _buildProfilePage(),
        ],
      ),
    );
  }

  Widget _buildProfilePage() => ListView(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
    children: [
      Text(
        'Your profile',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      const Text(
        'Your municipal crew identity and account details.',
        style: TextStyle(color: Color(0xFF64748B)),
      ),
      const SizedBox(height: 18),
      _profileDetails(),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: CrewCredits(uid: widget.user.uid),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Request leave'),
              subtitle: const Text('Choose upcoming dates and add a reason'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _openLeaveRequest,
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('About Pravah Saarthi'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showDetails(
                'About Pravah Saarthi',
                const Text(
                  'View drain-cleaning duties assigned to your municipal '
                  'account. Tasks update automatically when assignments change.',
                ),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.contact_support_outlined),
              title: const Text('Contact support'),
              subtitle: const Text('Municipal Board account assistance'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _showDetails(
                'Contact support',
                const Text(
                  'For account support, assignment issues, or a password reset, '
                  'contact your Municipal Board office.',
                ),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            SwitchListTile(
              secondary: const Icon(Icons.bug_report_outlined),
              title: const Text('Enable debug mode'),
              subtitle: Text(
                _debugModeEnabled
                    ? 'Preview controls enabled; live app functions are unchanged.'
                    : 'Unlock preview controls with the demo PIN.',
              ),
              value: _debugModeEnabled,
              onChanged: (enabled) {
                if (!enabled) {
                  setState(() => _debugModeEnabled = false);
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CrewDebugToolPage(
                      onDebugModeChanged: (value) {
                        if (mounted) {
                          setState(() => _debugModeEnabled = value);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      OutlinedButton.icon(
        onPressed: widget.onLogout,
        icon: const Icon(Icons.logout_rounded),
        label: const Text('Log out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFB91C1C),
          side: const BorderSide(color: Color(0xFFFECACA)),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    ],
  );
}

class _TaskRangeSelector extends StatelessWidget {
  const _TaskRangeSelector({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _labels = ['Last week', 'Active tasks'];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF1F2),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        for (var index = 0; index < _labels.length; index++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Material(
                color: selectedIndex == index
                    ? const Color(0xFF0F766E)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () => onSelected(index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 11,
                    ),
                    child: Text(
                      _labels[index],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selectedIndex == index
                            ? Colors.white
                            : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _CrewBottomNavigation extends StatelessWidget {
  const _CrewBottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _destinations = [
    (icon: Icons.task_alt_outlined, activeIcon: Icons.task_alt, label: 'Tasks'),
    (
      icon: Icons.add_a_photo_outlined,
      activeIcon: Icons.add_a_photo_rounded,
      label: 'Report',
    ),
    (
      icon: Icons.history_outlined,
      activeIcon: Icons.history_rounded,
      label: 'Activity',
    ),
    (
      icon: Icons.badge_outlined,
      activeIcon: Icons.badge_rounded,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFDCE5E7))),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 62,
        child: Row(
          children: [
            for (var index = 0; index < _destinations.length; index++)
              Expanded(
                child: InkWell(
                  onTap: () => onSelected(index),
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 32,
                        height: 3,
                        decoration: BoxDecoration(
                          color: selectedIndex == index
                              ? const Color(0xFF0F766E)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Icon(
                        selectedIndex == index
                            ? _destinations[index].activeIcon
                            : _destinations[index].icon,
                        color: selectedIndex == index
                            ? const Color(0xFF0F766E)
                            : const Color(0xFF64748B),
                        size: 22,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _destinations[index].label,
                        style: TextStyle(
                          color: selectedIndex == index
                              ? const Color(0xFF0F766E)
                              : const Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: selectedIndex == index
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class CrewIdentityCard extends StatelessWidget {
  const CrewIdentityCard({
    super.key,
    required this.name,
    required this.role,
    required this.municipalId,
    required this.email,
    required this.initials,
    required this.avatarColor,
  });

  final String name;
  final String role;
  final String municipalId;
  final String email;
  final String initials;
  final Color avatarColor;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0F766E), Color(0xFF124170)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: avatarColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MUNICIPAL CREW',
                      style: TextStyle(
                        color: Color(0xFFCCFBF1),
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'ACTIVE FIELD ACCOUNT',
                      style: TextStyle(
                        color: Color(0xFFD1FAE5),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.verified_rounded, color: Color(0xFFA7F3D0)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MUNICIPAL ID',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              SelectableText(
                municipalId.isEmpty ? 'Not assigned' : municipalId,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.alternate_email_rounded,
                    size: 17,
                    color: Color(0xFF64748B),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      email.isEmpty ? 'Crew account' : email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Text(
                    'Pravah Saarthi',
                    style: TextStyle(
                      color: Color(0xFF0F766E),
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
