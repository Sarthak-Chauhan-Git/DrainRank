import 'package:flutter/material.dart';

const _localDebugPin = '12345678';

class LocalCitizenDebugApp extends StatefulWidget {
  const LocalCitizenDebugApp({super.key});

  @override
  State<LocalCitizenDebugApp> createState() => _LocalCitizenDebugAppState();
}

class _LocalCitizenDebugAppState extends State<LocalCitizenDebugApp> {
  bool _unlocked = false;
  String? _error;
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final _pinController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final List<_DemoCitizenReport> _reports = [];
  String _category = 'Blocked drain';
  int _selectedTab = 0;

  @override
  void dispose() {
    _pinController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _unlock() {
    if (_pinController.text != _localDebugPin) {
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
    final reportNumber = _reports.length + 1;
    setState(() {
      _reports.insert(
        0,
        _DemoCitizenReport(
          id: 'LOCAL-${DateTime.now().millisecondsSinceEpoch}-$reportNumber',
          category: _category,
          location: location,
          description: description,
        ),
      );
      _locationController.clear();
      _descriptionController.clear();
      _selectedTab = 1;
    });
    _showMessage('Local test report submitted. No server was contacted.');
  }

  void _showMessage(String message) {
    final messenger = _messengerKey.currentState;
    if (messenger == null) {
      throw StateError('The local debug workspace is not ready.');
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pravah Citizen Local Debug',
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
    appBar: AppBar(title: const Text('Pravah · Local Debug')),
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
                'Local citizen test workspace',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'This build uses temporary in-memory sample data only. It does '
                'not connect to Supabase, save reports, access GPS, or upload '
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
      title: const Text('Pravah · Local Debug'),
      actions: [
        IconButton(
          tooltip: 'Reset local test data',
          onPressed: () => setState(_reports.clear),
          icon: const Icon(Icons.delete_sweep_outlined),
        ),
      ],
    ),
    body: IndexedStack(
      index: _selectedTab,
      children: [_buildReportForm(), _buildReports(), _buildProfile()],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _selectedTab,
      onDestinationSelected: (index) => setState(() => _selectedTab = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.add_a_photo_outlined),
          label: 'Report',
        ),
        NavigationDestination(
          icon: Icon(Icons.track_changes_outlined),
          label: 'Track',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline),
          label: 'Profile',
        ),
      ],
    ),
  );

  Widget _buildReportForm() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Report a drainage issue',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Create a local sample that you can advance through the demo workflow.',
      ),
      const SizedBox(height: 20),
      DropdownButtonFormField<String>(
        initialValue: _category,
        decoration: const InputDecoration(
          labelText: 'Issue type',
          border: OutlineInputBorder(),
        ),
        items:
            const [
                  'Blocked drain',
                  'Waterlogging',
                  'Overflow',
                  'Needs inspection',
                  'Other',
                ]
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
        onChanged: (value) => setState(() => _category = value ?? _category),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _locationController,
        decoration: const InputDecoration(
          labelText: 'Location or landmark',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _descriptionController,
        minLines: 3,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Issue details',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: _submitReport,
        icon: const Icon(Icons.send_outlined),
        label: const Text('Submit local report'),
      ),
      const SizedBox(height: 12),
      const Text(
        'Local simulation: camera, GPS, network, and Supabase are disabled.',
        style: TextStyle(color: Color(0xFF64748B)),
      ),
    ],
  );

  Widget _buildReports() {
    if (_reports.isEmpty) {
      return const Center(child: Text('No local reports yet.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reports.length,
      itemBuilder: (context, index) {
        final report = _reports[index];
        return Card(
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
                const SizedBox(height: 4),
                Text('${report.id} · ${report.location}'),
                const SizedBox(height: 6),
                Text(report.description),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: report.status,
                  decoration: const InputDecoration(
                    labelText: 'Simulate status',
                  ),
                  items:
                      const [
                            'Complaint received',
                            'Under verification',
                            'Cleaning queue',
                            'Resolved',
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) =>
                      setState(() => report.status = value ?? report.status),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Status simulation is stored only in this screen’s memory.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfile() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const CircleAvatar(
        radius: 32,
        child: Icon(Icons.person_outline_rounded, size: 32),
      ),
      const SizedBox(height: 12),
      Text(
        'Local test citizen',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Backend: disconnected\nStorage: in-memory only\nNo account or report '
        'data is persisted.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
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

class _DemoCitizenReport {
  _DemoCitizenReport({
    required this.id,
    required this.category,
    required this.location,
    required this.description,
  });

  final String id;
  final String category;
  final String location;
  final String description;
  String status = 'Complaint received';
}
