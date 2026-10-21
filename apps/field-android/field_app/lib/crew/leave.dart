part of '../main.dart';

class RequestLeavePage extends StatefulWidget {
  const RequestLeavePage({
    super.key,
    required this.currentUserUid,
    required this.crewName,
  });

  final String currentUserUid;
  final String crewName;

  @override
  State<RequestLeavePage> createState() => _RequestLeavePageState();
}

class _RequestLeavePageState extends State<RequestLeavePage> {
  final TextEditingController _reasonController = TextEditingController();
  final Set<DateTime> _selectedDates = <DateTime>{};
  late DateTime _visibleMonth;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  DateTime _dayOnly(DateTime value) => DateTime(value.year, value.month, value.day);

  DateTime get _tomorrow => _dayOnly(DateTime.now()).add(const Duration(days: 1));

  bool _isSelectable(DateTime day) => !day.isBefore(_tomorrow);

  String _monthTitle(DateTime month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[month.month - 1]} ${month.year}';
  }

  void _changeMonth(int offset) {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    final current = DateTime(DateTime.now().year, DateTime.now().month);
    if (next.isBefore(current)) return;
    setState(() => _visibleMonth = next);
  }

  void _toggleDate(DateTime day) {
    final normalized = _dayOnly(day);
    if (!_isSelectable(normalized)) return;
    setState(() {
      if (!_selectedDates.add(normalized)) _selectedDates.remove(normalized);
    });
  }

  Future<void> _submitLeave() async {
    if (_submitting) return;
    if (_selectedDates.isEmpty) {
      showAppMessage(context, 'Select at least one future leave date.');
      return;
    }
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      showAppMessage(context, 'Enter a reason for leave.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final dates = _selectedDates.toList()..sort();
      await FirebaseFirestore.instance.collection('leaveRequests').add({
        'crewUid': widget.currentUserUid,
        'crewName': widget.crewName,
        'dates': dates.map(_dateKey).toList(),
        'reason': reason,
        'status': 'Pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() {
        _selectedDates.clear();
        _reasonController.clear();
      });
      showAppMessage(context, 'Leave request submitted for admin approval.');
    } on FirebaseException catch (e) {
      if (mounted) {
        showAppMessage(context, e.code == 'permission-denied'
            ? 'Leave request was blocked by Firestore rules. Add leaveRequests permissions.'
            : 'Could not submit leave request: ${e.message ?? e.code}');
      }
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not submit leave request: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _calendar() {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final leading = first.weekday - 1;
    const week = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text(_monthTitle(_visibleMonth), textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17))),
            IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: 8),
          Row(children: [for (final d in week) Expanded(child: Text(d,
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall))]),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
            itemCount: leading + daysInMonth,
            itemBuilder: (context, index) {
              if (index < leading) return const SizedBox.shrink();
              final day = DateTime(_visibleMonth.year, _visibleMonth.month, index - leading + 1);
              final enabled = _isSelectable(day);
              final selected = _selectedDates.contains(_dayOnly(day));
              return Padding(
                padding: const EdgeInsets.all(2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: enabled ? () => _toggleDate(day) : null,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? Theme.of(context).colorScheme.primary : null,
                    ),
                    child: Text('${day.day}', style: TextStyle(
                      color: selected
                          ? Theme.of(context).colorScheme.onPrimary
                          : enabled ? null : Theme.of(context).disabledColor,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    )),
                  ),
                ),
              );
            },
          ),
        ]),
      ),
    );
  }

  Widget _selectedDateChips() {
    final dates = _selectedDates.toList()..sort();
    if (dates.isEmpty) {
      return const Text('No dates selected yet. Tap future dates in the calendar.');
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: dates.map((date) => InputChip(
        label: Text(_prettyDate(date)),
        onDeleted: () => _toggleDate(date),
      )).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Leave')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text('Select Leave Date', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Choose one or more future dates. Past dates and today cannot be selected.'),
          const SizedBox(height: 12),
          _calendar(),
          const SizedBox(height: 14),
          Text('Selected Leave Dates', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _selectedDateChips(),
          const SizedBox(height: 20),
          Text('Reason for Leave', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonController,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(hintText: 'Enter reason for leave...'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _submitting ? null : _submitLeave,
            icon: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.event_available_outlined),
            label: Text(_submitting ? 'Submitting...' : 'REQUEST LEAVE'),
          ),
          const SizedBox(height: 26),
          Text('My Leave Requests', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance.collection('leaveRequests')
                .where('crewUid', isEqualTo: widget.currentUserUid).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text('Unable to load leave requests: ${snapshot.error}');
              }
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs.toList();
              docs.sort((a, b) {
                final aa = a.data()['requestedAt'];
                final bb = b.data()['requestedAt'];
                final am = aa is Timestamp ? aa.millisecondsSinceEpoch : 0;
                final bm = bb is Timestamp ? bb.millisecondsSinceEpoch : 0;
                return bm.compareTo(am);
              });
              if (docs.isEmpty) return const Text('No leave requests submitted yet.');
              return Column(children: docs.map((doc) {
                final data = doc.data();
                final dates = data['dates'] is List ? (data['dates'] as List).whereType<String>().toList() : <String>[];
                final status = (data['status'] ?? 'Pending').toString();
                final statusColor = status == 'Approved' ? const Color(0xFF059669)
                    : status == 'Rejected' ? const Color(0xFFB91C1C) : Colors.orange.shade800;
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text(dates.isEmpty ? 'Leave request' : dates.join(', ')),
                    subtitle: Text((data['reason'] ?? '').toString()),
                    trailing: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
                  ),
                );
              }).toList());
            },
          ),
        ],
      ),
    );
  }
}
