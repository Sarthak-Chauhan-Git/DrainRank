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
  FieldPriorityAnalysis? _priorityAnalysis;
  String? _priorityError;
  Uint8List? _photoBytes;
  DateTime? _capturedAt;
  bool? _bottleDetected;
  ObjectDetectionResult? _detectionResult;
  String? _bottleDetectionError;
  bool _loadingWards = true;
  bool _busy = false;
  String? _error;

  double? get _priorityScore {
    final analysis = _priorityAnalysis;
    if (analysis == null) return null;
    return FieldPriorityAnalyzer.priorityScore(
      issueCategory: _category,
      urgent: analysis.urgent,
      matchedDrain: analysis.matchedDrain,
    );
  }

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
      final originalBytes = await capture.image.readAsBytes();
      ObjectDetectionResult? detectionResult;
      String? bottleDetectionError;
      try {
        detectionResult = await BottleDetector.instance.detectObjects(
          originalBytes,
        );
      } catch (error) {
        bottleDetectionError = error.toString();
        debugPrint('Bottle detection failed: $error');
      }
      final bytes = embedGpsExifInJpeg(
        originalBytes,
        capturedPosition,
        capture.capturedAt,
      );
      FieldPriorityAnalysis? priorityAnalysis;
      String? priorityError;
      try {
        priorityAnalysis = await FieldPriorityAnalyzer().analyze(
          latitude: capturedPosition.latitude,
          longitude: capturedPosition.longitude,
          issueCategory: _category,
        );
      } catch (error) {
        priorityError = 'Could not verify nearby facilities: $error';
      }
      setState(() {
        _position = capturedPosition;
        _priorityAnalysis = priorityAnalysis;
        _priorityError = priorityError;
        _photoBytes = bytes;
        _capturedAt = capture.capturedAt;
        _bottleDetected = detectionResult?.bottleDetected;
        _detectionResult = detectionResult;
        _bottleDetectionError = bottleDetectionError;
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
          'p_linked_drain_id':
              _priorityAnalysis?.matchedDrain?.drainId ?? 'PROVISIONAL-PIN',
          'p_is_urgent_flagged': _priorityAnalysis?.urgent ?? false,
          'p_estimated_priority_score':
              _priorityScore ??
              FieldPriorityAnalyzer.priorityScore(
                issueCategory: _category,
                urgent: false,
              ),
        },
      );
      if (!mounted) return;
      _descriptionController.clear();
      _locationController.clear();
      setState(() {
        _position = null;
        _priorityAnalysis = null;
        _priorityError = null;
        _photoBytes = null;
        _capturedAt = null;
        _detectionResult = null;
        _bottleDetected = null;
        _bottleDetectionError = null;
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
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. GPS-tagged Photograph',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Capture the cleaning issue at its location. The photo and '
                'coordinates are attached to this report.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _capturePhoto,
                icon: const Icon(Icons.location_on_outlined),
                label: Text(
                  _position == null
                      ? 'Capture GPS-tagged photo'
                      : 'Retake GPS-tagged photo',
                ),
              ),
              if (_position != null) ...[
                const SizedBox(height: 8),
                Text(
                  'GPS: ${_position!.latitude.toStringAsFixed(5)}, '
                  '${_position!.longitude.toStringAsFixed(5)} '
                  '(±${_position!.accuracy.toStringAsFixed(0)} m)',
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                  ),
                ),
              ],
              if (_photoBytes != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: DetectedObjectImage(
                    image: MemoryImage(_photoBytes!),
                    result: _detectionResult,
                    height: 180,
                  ),
                ),
                if (_bottleDetected != null || _bottleDetectionError != null)
                  BottleDetectionNotice(
                    bottleDetected: _bottleDetected,
                    error: _bottleDetectionError,
                  ),
              ],
            ],
          ),
        ),
      ),
      if (_position != null)
        Column(
          children: [const SizedBox(height: 12), _buildPriorityAssessment()],
        ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '2. Issue Classification',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              RadioGroup<String>(
                groupValue: _category,
                onChanged: (value) {
                  if (!_busy && value != null) {
                    setState(() => _category = value);
                  }
                },
                child: Column(
                  children: _categories.entries
                      .map(
                        (entry) => RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.value),
                          value: entry.key,
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '3. Location and Description',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              if (_loadingWards)
                const LinearProgressIndicator()
              else if (_wards.isEmpty)
                const Text('No wards are configured for report credits.')
              else
                DropdownButtonFormField<String>(
                  initialValue: _ward,
                  decoration: const InputDecoration(labelText: 'Ward'),
                  items: _wards
                      .map(
                        (ward) =>
                            DropdownMenuItem(value: ward, child: Text(ward)),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _ward = value),
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
            ],
          ),
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

  Widget _buildPriorityAssessment() {
    final position = _position!;
    final analysis = _priorityAnalysis;
    final nearest = analysis?.nearestPlace;
    final score =
        _priorityScore ??
        FieldPriorityAnalyzer.priorityScore(
          issueCategory: _category,
          urgent: false,
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.insights_outlined, color: Color(0xFF0F766E)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Location priority assessment',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${score.toStringAsFixed(1)} / 100',
                  style: const TextStyle(
                    color: Color(0xFF0F766E),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: analysis?.urgent == true
                    ? const Color(0xFFFFE4E6)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: analysis?.urgent == true
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFFDCE5E7),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    analysis?.urgent == true
                        ? Icons.priority_high_rounded
                        : Icons.verified_outlined,
                    color: analysis?.urgent == true
                        ? const Color(0xFF991B1B)
                        : const Color(0xFF475569),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      analysis?.urgent == true
                          ? 'High urgency detected: ${nearest!.name} is '
                                '${nearest.distanceMeters.toStringAsFixed(0)} m away.'
                          : analysis == null
                          ? 'Priority lookup unavailable; showing the standard '
                                'location score.'
                          : 'Standard priority: no matching facility within 500 m.',
                      style: TextStyle(
                        color: analysis?.urgent == true
                            ? const Color(0xFF7F1D1D)
                            : const Color(0xFF475569),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_priorityError != null) ...[
              const SizedBox(height: 4),
              Text(
                _priorityError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (analysis?.matchedDrain != null) ...[
              const SizedBox(height: 4),
              Text(
                'Linked drain: ${analysis!.matchedDrain!.drainId} '
                '(${analysis.matchedDrain!.name})',
                style: const TextStyle(color: Color(0xFF475569)),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              height: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(
                      position.latitude,
                      position.longitude,
                    ),
                    initialZoom: 14.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.field_app',
                    ),
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: LatLng(position.latitude, position.longitude),
                          radius: fieldPriorityRadiusMeters,
                          useRadiusInMeter: true,
                          color: const Color(0xFF0F766E).withValues(alpha: .12),
                          borderColor: const Color(0xFF0F766E),
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(position.latitude, position.longitude),
                          width: 36,
                          height: 36,
                          child: const Icon(
                            Icons.location_on,
                            color: Color(0xFFB91C1C),
                            size: 34,
                          ),
                        ),
                        for (final place
                            in analysis?.nearbyPlaces ??
                                const <FieldNearbyPlace>[])
                          Marker(
                            point: LatLng(place.latitude, place.longitude),
                            width: 32,
                            height: 32,
                            child: Tooltip(
                              message:
                                  '${place.name} · '
                                  '${place.distanceMeters.toStringAsFixed(0)} m',
                              child: const Icon(
                                Icons.local_hospital,
                                color: Color(0xFF7C3AED),
                                size: 26,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Geoapify facility search radius: 500 m. Score follows the '
              'citizen app DrainRank formula.',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
      ),
    );
  }
}
