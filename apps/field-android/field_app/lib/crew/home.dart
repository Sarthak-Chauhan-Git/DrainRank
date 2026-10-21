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
// 0 = previous seven days; 1 = today; 2 = upcoming seven days.
  int _selectedTab = 1;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _tasksStream;

  @override
  void initState() {
    super.initState();
    _openTaskStream();
  }

  void _openTaskStream() {
    // Keep this query aligned with the /tasks Firestore security rule.
    // A permission-denied response must be fixed in Firestore Rules.
    final uid = FirebaseAuth.instance.currentUser?.uid ?? widget.user.uid;
    debugPrint('DRAINRANK task query: project=${Firebase.app().options.projectId}, uid=$uid');
    _tasksStream = FirebaseFirestore.instance
        .collection('tasks')
        .where('assignedToUid', arrayContains: uid)
        .snapshots();
  }

  DateTime _dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  String get _crewName {
    final name = (widget.profile['fullName'] ??
        widget.profile['name'] ??
        widget.user.displayName ??
        '')
        .toString()
        .trim();
    return name.isNotEmpty
        ? name
        : (widget.user.email?.split('@').first ?? 'Crew Member');
  }

  List<DateTime> _visibleDays() {
    final today = _dayOnly(DateTime.now());
    if (_selectedTab == 1) return [today];
    if (_selectedTab == 0) {
      return List.generate(7, (i) => today.subtract(Duration(days: 7 - i)));
    }
    return List.generate(7, (i) => today.add(Duration(days: i + 1)));
  }

// Handles both '08:00 AM' and '13:00' time strings for chronological sorting.
  int _timeInMinutes(String? raw) {
    if (raw == null) return 9999;
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$', caseSensitive: false)
        .firstMatch(raw.trim());
    if (match == null) return 9999;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)?.toUpperCase();
    if (minute > 59 || hour > (period == null ? 23 : 12) || hour == 0 && period != null) {
      return 9999;
    }
    if (period != null) hour = (hour % 12) + (period == 'PM' ? 12 : 0);
    return hour * 60 + minute;
  }

  void _refreshTasks() {
    setState(_openTaskStream);
    showAppMessage(context, 'Refreshing assigned tasks...');
  }

  void _showDetails(String title, Widget content) {
    Navigator.of(context).pop(); // Close drawer before opening detail sheet.
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
              Text(title, style: Theme.of(sheetContext).textTheme.headlineSmall),
              const SizedBox(height: 16),
              content,
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileDetails() {
    final municipalId = (widget.profile['municipalId'] ?? '').toString().trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: const Text('Name'),
          subtitle: Text(_crewName),
        ),
        if (municipalId.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Municipal ID'),
            subtitle: Text(municipalId),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Account'),
          subtitle: const Text('Municipal crew member'),
        ),
      ],
    );
  }

  Future<void> _logoutFromMenu() async {
    Navigator.of(context).pop();
    await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final visibleDays = _visibleDays();
    final visibleKeys = visibleDays.map(_dateKey).toSet();
    final heading = switch (_selectedTab) {
      0 => 'Past 7 Days',
      1 => 'Today',
      _ => 'Next 7 Days',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('DRAINRANK'),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(_crewName),
                accountEmail: const Text('Municipal Crew Member'),
                currentAccountPicture: const CircleAvatar(
                  child: Icon(Icons.person, size: 34),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Your Profile'),
                onTap: () => _showDetails('Your Profile', _profileDetails()),
              ),
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text('Your Activity'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CrewActivityPage(currentUserUid: widget.user.uid),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('Request Leave'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RequestLeavePage(
                        currentUserUid: widget.user.uid,
                        crewName: _crewName,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Info'),
                onTap: () => _showDetails(
                  'About the App',
                  const Text('View drain-cleaning duties assigned to your municipal account. Tasks update automatically when assignments change.'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.contact_support_outlined),
                title: const Text('Contact'),
                onTap: () => _showDetails(
                  'Contact',
                  const Text('For account support, assignment issues, or a password reset, contact your Municipal Board office.'),
                ),
              ),
              const Spacer(),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Log Out'),
                onTap: _logoutFromMenu,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history_toggle_off),
            label: 'Past 7 Days',
          ),
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Next 7 Days',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _tasksStream,
        builder: (context, snapshot) {
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
                      snapshot.error is FirebaseException &&
                          (snapshot.error as FirebaseException).code == 'permission-denied'
                          ? 'Firestore rejected the assigned-tasks query. '
                            'Publish the matching /tasks security rule. '
                            'Project: ${Firebase.app().options.projectId}\n'
                            'Signed-in UID: ${FirebaseAuth.instance.currentUser?.uid ?? widget.user.uid}\n'
                            'Check that assignedToUid contains this UID as an array item.'
                          : 'Check your internet connection and try again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: _refreshTasks, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final allAssignedTasks = snapshot.data?.docs ?? [];
          final filtered = allAssignedTasks
              .where((doc) => visibleKeys.contains(doc.data()['dateKey']))
              .toList();
          final byDate = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final doc in filtered) {
            final dateKey = doc.data()['dateKey'] as String;
            byDate.putIfAbsent(dateKey, () => []).add(doc);
          }
          for (final tasks in byDate.values) {
            tasks.sort((a, b) => _timeInMinutes(a.data()['startTime']?.toString())
                .compareTo(_timeInMinutes(b.data()['startTime']?.toString())));
          }

          // The Today tab also includes earlier assignments for which this
          // crew member has not submitted any work update yet.
          final overdueTasks = _selectedTab == 1
              ? allAssignedTasks.where((doc) {
                  final day = _parseTaskDate(doc.data()['dateKey']);
                  return day != null && day.isBefore(_todayOnly());
                }).toList()
              : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          overdueTasks.sort((a, b) {
            final dayA = _parseTaskDate(a.data()['dateKey'])!;
            final dayB = _parseTaskDate(b.data()['dateKey'])!;
            final byDay = dayA.compareTo(dayB); // oldest overdue task first
            if (byDay != 0) return byDay;
            return _timeInMinutes(a.data()['startTime']?.toString())
                .compareTo(_timeInMinutes(b.data()['startTime']?.toString()));
          });

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              Text('Hello, $_crewName!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Center(child: CrewCredits(uid: widget.user.uid, compact: true)),
              const SizedBox(height: 12),
              Text(heading,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(
                _selectedTab == 1
                    ? _prettyDate(visibleDays.first)
                    : '${_prettyDate(visibleDays.first)} – ${_prettyDate(visibleDays.last)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (filtered.isEmpty && _selectedTab != 1)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        const Icon(Icons.event_busy_outlined, size: 42),
                        const SizedBox(height: 12),
                        Text('No tasks assigned for $heading', textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        const Text('New assignments will appear here automatically.', textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              if (filtered.isEmpty && _selectedTab == 1)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No tasks assigned for today.', textAlign: TextAlign.center),
                  ),
                ),
              for (final date in visibleDays)
                if (byDate[_dateKey(date)]?.isNotEmpty == true) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                    child: Text(
                      _prettyDate(date),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (var i = 0; i < byDate[_dateKey(date)]!.length; i++)
                    _DrainTaskCard(
                      data: byDate[_dateKey(date)]![i].data(),
                      number: i + 1,
                      taskId: byDate[_dateKey(date)]![i].id,
                      currentUserUid: widget.user.uid,
                      showCredits: true,
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
              if (_selectedTab == 1) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 18, 4, 10),
                  child: Text('Overdue Tasks',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                if (overdueTasks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('No overdue tasks.', textAlign: TextAlign.center),
                  ),
                for (final overdueTask in overdueTasks)
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: overdueTask.reference
                        .collection('workUpdates')
                        .where('submittedByUid', isEqualTo: widget.user.uid)
                        .limit(1)
                        .snapshots(),
                    builder: (context, workSnapshot) {
                      // Hide overdue work once this member has submitted it.
                      if (!workSnapshot.hasData || workSnapshot.hasError ||
                          workSnapshot.data!.docs.isNotEmpty) {
                        return const SizedBox.shrink();
                      }
                      return _DrainTaskCard(
                        data: overdueTask.data(),
                        number: 0,
                        taskId: overdueTask.id,
                        currentUserUid: widget.user.uid,
                        showCredits: true,
                        isOverdue: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TaskDetailsPage(
                              taskId: overdueTask.id,
                              currentUserUid: widget.user.uid,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
