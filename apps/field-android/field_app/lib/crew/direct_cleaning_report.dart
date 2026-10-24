part of '../main.dart';

class DirectCleaningReportPage extends StatefulWidget {
  const DirectCleaningReportPage({super.key, required this.user});

  final User user;

  @override
  State<DirectCleaningReportPage> createState() =>
      _DirectCleaningReportPageState();
}

class _DirectCleaningReportPageState extends State<DirectCleaningReportPage> {
  static const _categories = {
    'blocked_drain': 'Blocked drain',
    'waterlogging': 'Waterlogging',
    'overflow': 'Overflow',
    'other': 'Other cleaning issue',
  };

  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  String _category = 'blocked_drain';
  String? _ward;
  List<String> _wards = [];
  Position? _position;
  Uint8List? _photoBytes;
  DateTime? _capturedAt;
  bool _loadingWards = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadWards();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadWards() async {
    try {
      final result = await fieldBackend.rpc('list_direct_report_wards');
      final wards = (result as List).whereType<String>().toList()..sort();
      if (!mounted) return;
      setState(() {
        _wards = wards;
        _ward = wards.isEmpty ? null : wards.first;
        _loadingWards = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingWards = false;
        _error = 'Could not load wards: $error';
      });
    }
  }

  Future<Position> _getPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw StateError('Turn on device location services to continue.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('Location permission is required for this report.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _capturePhoto() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _getPosition();
      if (!mounted) return;
      final capture = await Navigator.of(context).push<LiveCameraCapture>(
        MaterialPageRoute(builder: (_) => const LiveWorkCameraPage()),
      );
      if (capture == null || !mounted) return;
      final capturedPosition = await _getPosition();
      if (capturedPosition.accuracy < 0) {
        throw StateError('The device did not return a valid GPS accuracy.');
      }
      final bytes = embedGpsExifInJpeg(
        await capture.image.readAsBytes(),
        capturedPosition,
        capture.capturedAt,
      );
      setState(() {
        _position = capturedPosition;
        _photoBytes = bytes;
        _capturedAt = capture.capturedAt;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not capture photo: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    final position = _position;
    final photoBytes = _photoBytes;
    final capturedAt = _capturedAt;
    if (_ward == null ||
        position == null ||
        photoBytes == null ||
        capturedAt == null) {
      setState(() => _error = 'Select a ward and capture a GPS-tagged photo.');
      return;
    }
    if (_descriptionController.text.trim().isEmpty ||
        _locationController.text.trim().isEmpty) {
      setState(() => _error = 'Enter the location and issue details.');
      return;
    }

    final reportId =
        'DCR-${DateTime.now().toUtc().millisecondsSinceEpoch}-${math.Random.secure().nextInt(10000).toString().padLeft(4, '0')}';
    final photoPath = '${widget.user.uid}/$reportId.jpg';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fieldBackend.storage
          .from('field-direct-reports')
          .uploadBinary(
            photoPath,
            photoBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );
      await fieldBackend.rpc(
        'submit_direct_cleaning_report',
        params: {
          'p_report_id': reportId,
          'p_issue_category': _category,
          'p_description': _descriptionController.text.trim(),
          'p_ward': _ward,
          'p_location_description': _locationController.text.trim(),
          'p_latitude': position.latitude,
          'p_longitude': position.longitude,
          'p_accuracy_meters': position.accuracy,
          'p_photo_path': photoPath,
          'p_captured_at': capturedAt.toUtc().toIso8601String(),
        },
      );
      if (!mounted) return;
      _descriptionController.clear();
      _locationController.clear();
      setState(() {
        _position = null;
        _photoBytes = null;
        _capturedAt = null;
      });
      showAppMessage(
        context,
        'Report $reportId sent directly to the cleaning queue for verification.',
      );
    } catch (error) {
      try {
        await fieldBackend.storage.from('field-direct-reports').remove([
          photoPath,
        ]);
      } catch (cleanupError) {
        debugPrint('Could not remove unsubmitted report photo: $cleanupError');
      }
      if (mounted) setState(() => _error = 'Could not submit report: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text(
        'Report cleaning needed',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      const Text(
        'Send a verified field observation directly to the cleaning queue. '
        'A supervisor reviews accuracy before report credits are awarded.',
        style: TextStyle(color: Color(0xFF64748B)),
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        initialValue: _categories.containsKey(_category) ? _category : null,
        decoration: const InputDecoration(labelText: 'Issue type'),
        items: _categories.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(),
        onChanged: _busy
            ? null
            : (value) => setState(() => _category = value ?? _category),
      ),
      const SizedBox(height: 12),
      if (_loadingWards)
        const LinearProgressIndicator()
      else if (_wards.isEmpty)
        const Text('No wards are configured for report credits.')
      else
        DropdownButtonFormField<String>(
          initialValue: _ward,
          decoration: const InputDecoration(labelText: 'Ward'),
          items: _wards
              .map((ward) => DropdownMenuItem(value: ward, child: Text(ward)))
              .toList(),
          onChanged: _busy ? null : (value) => setState(() => _ward = value),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: _locationController,
        enabled: !_busy,
        decoration: const InputDecoration(
          labelText: 'Location / nearby landmark',
          hintText: 'Road, crossing, or nearby landmark',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _descriptionController,
        enabled: !_busy,
        minLines: 3,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'What needs cleaning?',
          alignLabelWithHint: true,
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _busy ? null : _capturePhoto,
        icon: const Icon(Icons.location_on_outlined),
        label: Text(
          _position == null
              ? 'Capture GPS-tagged photo'
              : 'Retake GPS-tagged photo',
        ),
      ),
      if (_position != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'GPS: ${_position!.latitude.toStringAsFixed(5)}, '
            '${_position!.longitude.toStringAsFixed(5)} '
            '(±${_position!.accuracy.toStringAsFixed(0)} m)',
            style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
          ),
        ),
      if (_photoBytes != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_photoBytes!, height: 180, fit: BoxFit.cover),
          ),
        ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy || _loadingWards || _wards.isEmpty ? null : _submit,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.send_rounded),
        label: Text(_busy ? 'Submitting...' : 'Send to cleaning queue'),
      ),
    ],
  );
}
