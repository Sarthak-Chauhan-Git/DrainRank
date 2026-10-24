part of '../main.dart';

class CrewDebugToolPage extends StatefulWidget {
  const CrewDebugToolPage({super.key});

  @override
  State<CrewDebugToolPage> createState() => _CrewDebugToolPageState();
}

class _CrewDebugToolPageState extends State<CrewDebugToolPage> {
  bool _unlocked = false;
  String? _error;
  final _pinController = TextEditingController();
  bool _showTasks = true;
  bool _showActivity = true;
  bool _showLeave = true;
  bool _showLocation = true;
  bool _showDirectReport = true;
  String _taskStatus = 'In progress';
  String _leaveStatus = 'Pending approval';
  String _directReportStatus = 'Awaiting verification';
  int _activityMonths = 1;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  void _unlock() {
    if (_pinController.text != _debugToolPin) {
      setState(() => _error = 'Incorrect demo PIN.');
      return;
    }
    setState(() {
      _unlocked = true;
      _error = null;
    });
  }

  Widget _previewCard(String title, Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Debug Mode')),
    body: !_unlocked
        ? ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.lock_outline_rounded, size: 42),
              const SizedBox(height: 12),
              const Text(
                'Enter the demo PIN to open local previews.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'Demo PIN',
                  counterText: '',
                ),
                onSubmitted: (_) => _unlock(),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _unlock,
                child: const Text('Unlock local previews'),
              ),
              const SizedBox(height: 12),
              const Text(
                'The demo PIN is visible in the app binary. Debug controls only change previews on this screen; they never write to Supabase or alter GPS on submitted evidence.',
                style: TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
              ),
            ],
          )
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              const Text(
                'Local demo previews',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Preview-only controls. Live assignments, evidence, credits, leave requests, and GPS capture remain unchanged.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Sample task preview'),
                value: _showTasks,
                onChanged: (value) => setState(() => _showTasks = value),
              ),
              if (_showTasks)
                _previewCard(
                  'DCR-DEMO-01 · Cleaning report',
                  DropdownButton<String>(
                    value: _taskStatus,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'Pending',
                        child: Text('Pending'),
                      ),
                      DropdownMenuItem(
                        value: 'In progress',
                        child: Text('In progress'),
                      ),
                      DropdownMenuItem(
                        value: 'Completed',
                        child: Text('Completed'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _taskStatus = value ?? _taskStatus),
                  ),
                ),
              SwitchListTile(
                title: const Text('Direct cleaning report preview'),
                subtitle: const Text(
                  'Simulate queue review and sample credits locally.',
                ),
                value: _showDirectReport,
                onChanged: (value) => setState(() => _showDirectReport = value),
              ),
              if (_showDirectReport)
                _previewCard(
                  'DCR-DEMO-02 · Blocked drain · Ward 1',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sent directly to the cleaning queue without inspection.',
                      ),
                      DropdownButton<String>(
                        value: _directReportStatus,
                        isExpanded: true,
                        items: const [
                          DropdownMenuItem(
                            value: 'Awaiting verification',
                            child: Text('Awaiting verification'),
                          ),
                          DropdownMenuItem(
                            value: 'Verified',
                            child: Text('Verified'),
                          ),
                          DropdownMenuItem(
                            value: 'Rejected',
                            child: Text('Rejected'),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _directReportStatus =
                              value ?? _directReportStatus,
                        ),
                      ),
                      Text(
                        _directReportStatus == 'Verified'
                            ? 'Sample credits awarded: 120'
                            : _directReportStatus == 'Rejected'
                            ? 'No credits awarded.'
                            : 'Credits are held until verification.',
                      ),
                    ],
                  ),
                ),
              SwitchListTile(
                title: const Text('Sample activity and credits'),
                value: _showActivity,
                onChanged: (value) => setState(() => _showActivity = value),
              ),
              if (_showActivity)
                _previewCard(
                  'Activity preview',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: 1, label: Text('1 mo')),
                          ButtonSegment(value: 3, label: Text('3 mo')),
                          ButtonSegment(value: 6, label: Text('6 mo')),
                        ],
                        selected: {_activityMonths},
                        onSelectionChanged: (value) =>
                            setState(() => _activityMonths = value.first),
                      ),
                      const SizedBox(height: 8),
                      Text('Sample completed tasks: ${_activityMonths * 3}'),
                      Text('Sample credits: ${_activityMonths * 120}'),
                    ],
                  ),
                ),
              SwitchListTile(
                title: const Text('Sample leave request'),
                value: _showLeave,
                onChanged: (value) => setState(() => _showLeave = value),
              ),
              if (_showLeave)
                _previewCard(
                  'Leave request preview',
                  DropdownButton<String>(
                    value: _leaveStatus,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'Pending approval',
                        child: Text('Pending approval'),
                      ),
                      DropdownMenuItem(
                        value: 'Approved',
                        child: Text('Approved'),
                      ),
                      DropdownMenuItem(
                        value: 'Rejected',
                        child: Text('Rejected'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _leaveStatus = value ?? _leaveStatus),
                  ),
                ),
              SwitchListTile(
                title: const Text('Sample location preview'),
                subtitle: const Text(
                  'Visual sample only; never used by the camera or upload flow.',
                ),
                value: _showLocation,
                onChanged: (value) => setState(() => _showLocation = value),
              ),
              if (_showLocation)
                _previewCard(
                  'GPS preview',
                  const Text('28.6139, 77.2090 · demo coordinates'),
                ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => setState(() {
                  _showTasks = true;
                  _showActivity = true;
                  _showLeave = true;
                  _showLocation = true;
                  _showDirectReport = true;
                  _taskStatus = 'In progress';
                  _leaveStatus = 'Pending approval';
                  _directReportStatus = 'Awaiting verification';
                  _activityMonths = 1;
                }),
                child: const Text('Reset demo previews'),
              ),
            ],
          ),
  );
}
