import 'package:flutter/material.dart';

const _localFieldDebugPin = '12345678';

class LocalFieldDebugApp extends StatefulWidget {
  const LocalFieldDebugApp({super.key});

  @override
  State<LocalFieldDebugApp> createState() => _LocalFieldDebugAppState();
}

class _LocalFieldDebugAppState extends State<LocalFieldDebugApp> {
  bool _unlocked = false;
  String? _error;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _pinController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final List<_LocalCleaningReport> _reports = [];
  int _selectedTab = 0;
  int _credits = 0;
  String _taskStatus = 'In progress';
  String _category = 'Blocked drain';

  @override
  void dispose() {
    _pinController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _unlock() {
    if (_pinController.text != _localFieldDebugPin) {
      setState(() => _error = 'Incorrect demo PIN.');
      return;
    }
    setState(() {
      _unlocked = true;
      _error = null;
    });
  }

  void _submitReport() {
    final location = _locationController.text.trim();
    final description = _descriptionController.text.trim();
    if (location.isEmpty || description.isEmpty) {
      _showMessage('Enter a location and issue details.');
      return;
    }
    setState(() {
      _reports.insert(
        0,
        _LocalCleaningReport(
          id: 'LOCAL-DCR-${DateTime.now().millisecondsSinceEpoch}',
          category: _category,
          location: location,
          description: description,
        ),
      );
      _locationController.clear();
      _descriptionController.clear();
      _selectedTab = 2;
    });
    _showMessage('Local report added directly to the cleaning queue.');
  }

  void _showMessage(String message) {
    final messenger = _messengerKey.currentState;
    if (messenger == null) {
      throw StateError('The local debug workspace is not ready.');
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _reviewReport(_LocalCleaningReport report, String status) {
    if (report.status != 'Awaiting verification') return;
    setState(() {
      report.status = status;
      if (status == 'Verified') {
        report.creditsAwarded = 120;
        _credits += report.creditsAwarded;
      }
    });
  }

  void _resetLocalData() {
    setState(() {
      _reports.clear();
      _credits = 0;
      _taskStatus = 'In progress';
      _category = 'Blocked drain';
      _locationController.clear();
      _descriptionController.clear();
      _selectedTab = 0;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pravah Saarthi Local Debug',
    scaffoldMessengerKey: _messengerKey,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F766E)),
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    ),
    home: _unlocked ? _buildWorkspace() : _buildPinGate(),
  );

  Widget _buildPinGate() => Scaffold(
    appBar: AppBar(title: const Text('Pravah Saarthi · Local Debug')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 48),
              const SizedBox(height: 12),
              Text(
                'Local field test workspace',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'This build uses temporary in-memory data only. It does not '
                'connect to Supabase, save reports, access GPS, or upload '
                'photos.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'Demo PIN',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _unlock(),
              ),
              if (_error != null)
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _unlock,
                child: const Text('Unlock local tests'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Testing gate only; the PIN is included in this local build and '
                'is not production authentication.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildWorkspace() => Scaffold(
    appBar: AppBar(
      title: const Text('Pravah Saarthi · Local Debug'),
      actions: [
        IconButton(
          tooltip: 'Reset local test data',
          onPressed: _resetLocalData,
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ],
    ),
    body: IndexedStack(
      index: _selectedTab,
      children: [
        _buildTasks(),
        _buildReportForm(),
        _buildCleaningQueue(),
        _buildActivity(),
        _buildProfile(),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selectedTab,
      onDestinationSelected: (index) => setState(() => _selectedTab = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.task_alt_outlined),
          label: 'Tasks',
        ),
        NavigationDestination(
          icon: Icon(Icons.add_a_photo_outlined),
          label: 'Report',
        ),
        NavigationDestination(
          icon: Icon(Icons.cleaning_services_outlined),
          label: 'Queue',
        ),
        NavigationDestination(
          icon: Icon(Icons.history_outlined),
          label: 'Activity',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    ),
  );

  Widget _buildTasks() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text('Assigned tasks', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('Sample assignment · Ward 1 · Main Road'),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Clear blocked drainage channel',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _taskStatus,
                decoration: const InputDecoration(
                  labelText: 'Sample task status',
                ),
                items: const ['Pending', 'In progress', 'Completed']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _taskStatus = value ?? _taskStatus),
              ),
              const SizedBox(height: 8),
              const Text(
                'Task changes are kept in memory and are not assigned or saved.',
              ),
            ],
          ),
        ),
      ),
      const _LocalOnlyNotice(),
    ],
  );

  Widget _buildReportForm() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text(
        'Report cleaning needed',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Simulate a field report sent directly to the cleaning queue without '
        'inspection.',
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        initialValue: _category,
        decoration: const InputDecoration(labelText: 'Issue type'),
        items:
            const [
                  'Blocked drain',
                  'Waterlogging',
                  'Overflow',
                  'Other cleaning issue',
                ]
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
        onChanged: (value) => setState(() => _category = value ?? _category),
      ),
      const SizedBox(height: 12),
      const InputDecorator(
        decoration: InputDecoration(labelText: 'Ward'),
        child: Text('Ward 1 · sample ward'),
      ),
      TextField(
        controller: _locationController,
        decoration: const InputDecoration(
          labelText: 'Location or landmark',
          hintText: 'Road, crossing, or nearby landmark',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _descriptionController,
        minLines: 3,
        maxLines: 5,
        decoration: const InputDecoration(labelText: 'Issue details'),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _submitReport,
        icon: const Icon(Icons.send_outlined),
        label: const Text('Send local report to queue'),
      ),
      const SizedBox(height: 12),
      const _LocalOnlyNotice(),
    ],
  );

  Widget _buildCleaningQueue() {
    if (_reports.isEmpty) {
      return const Center(child: Text('No local cleaning reports yet.'));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Cleaning queue',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        for (final report in _reports)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.category,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('${report.id} · Ward 1 · ${report.location}'),
                  const SizedBox(height: 6),
                  Text(report.description),
                  const SizedBox(height: 10),
                  Text('Status: ${report.status}'),
                  if (report.creditsAwarded > 0)
                    Text('Local credits awarded: ${report.creditsAwarded}'),
                  if (report.status == 'Awaiting verification') ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => _reviewReport(report, 'Verified'),
                          child: const Text('Verify · award 120 credits'),
                        ),
                        OutlinedButton(
                          onPressed: () => _reviewReport(report, 'Rejected'),
                          child: const Text('Reject report'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        const _LocalOnlyNotice(),
      ],
    );
  }

  Widget _buildActivity() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text('Activity', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('Local credits'),
          subtitle: Text('$_credits credits'),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.task_alt_outlined),
          title: const Text('Sample task'),
          subtitle: Text(_taskStatus),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Direct cleaning reports'),
          subtitle: Text('${_reports.length} local reports'),
        ),
      ),
      const _LocalOnlyNotice(),
    ],
  );

  Widget _buildProfile() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text('Profile', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      const ListTile(
        leading: CircleAvatar(child: Text('DT')),
        title: Text('Demo field worker'),
        subtitle: Text('Local test account · Ward 1'),
      ),
      ListTile(
        leading: const Icon(Icons.workspace_premium_outlined),
        title: const Text('Local credits'),
        trailing: Text('$_credits'),
      ),
      const _LocalOnlyNotice(),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => setState(() {
          _unlocked = false;
          _pinController.clear();
        }),
        child: const Text('Lock local workspace'),
      ),
    ],
  );
}

class _LocalOnlyNotice extends StatelessWidget {
  const _LocalOnlyNotice();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 14),
    child: Text(
      'LOCAL TEST ONLY · No Supabase, GPS, photo upload, or database writes.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
    ),
  );
}

class _LocalCleaningReport {
  _LocalCleaningReport({
    required this.id,
    required this.category,
    required this.location,
    required this.description,
  });

  final String id;
  final String category;
  final String location;
  final String description;
  String status = 'Awaiting verification';
  int creditsAwarded = 0;
}
