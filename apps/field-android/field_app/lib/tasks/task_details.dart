part of '../main.dart';

class TaskDetailsPage extends StatefulWidget {
  const TaskDetailsPage({super.key, required this.taskId, required this.currentUserUid});
  final String taskId;
  final String currentUserUid;

  @override
  State<TaskDetailsPage> createState() => _TaskDetailsPageState();
}

class _PendingWorkPhoto {
  const _PendingWorkPhoto({required this.bytes, required this.position,
    required this.capturedAt, required this.slot});
  final Uint8List bytes;
  final Position position;
  final DateTime capturedAt;
  final int slot;
}

class _TaskDetailsPageState extends State<TaskDetailsPage> {
  final TextEditingController _descriptionController = TextEditingController();
  XFile? _image;
  Uint8List? _imageBytes;
  Position? _photoPosition;
  DateTime? _capturedAt;
  String? _photoAddress;
  bool _busy = false;
  String _saveStage = '';

  void _stage(String message) {
    debugPrint('Photo save: $message');
    if (mounted) setState(() => _saveStage = message);
  }

  String? _editingUpdateId;
  int _nextPhotoSlot = 1;
  final List<_PendingWorkPhoto> _pendingPhotos = [];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<Position> _getLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Enable device location services before taking a work photo.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission is required to attach a geo-tagged work photo.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<String?> _resolvePhotoAddress(Position position, {String? fallbackAddress}) async {
    try {
      final placemarks = await Geocoding().placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(const Duration(seconds: 8));
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = <String?>[
          place.name,
          place.street,
          place.subLocality,
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
          place.postalCode,
          place.country,
        ].whereType<String>().map((part) => part.trim())
            .where((part) => part.isNotEmpty).toList();
        final unique = <String>[];
        for (final part in parts) {
          if (!unique.contains(part)) unique.add(part);
        }
        if (unique.isNotEmpty) return unique.join(', ');
      }
    } catch (e) {
      // Reverse geocoding is not available on every browser/platform.
      debugPrint('Reverse geocoding unavailable: $e');
    }
    final fallback = fallbackAddress?.trim() ?? '';
    return fallback.isEmpty ? 'Address unavailable; GPS coordinates recorded'
        : 'Address lookup unavailable; task address: $fallback';
  }

  Future<void> _takePhoto({String? fallbackAddress}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
// Verify the GPS permission before launching the live camera.
      await _getLocation();
      if (!mounted) return;

// Unlike ImagePicker on the web, CameraPreview opens the live camera
// and never falls back to the file picker/gallery.
      final capture = await Navigator.of(context).push<LiveCameraCapture>(
        MaterialPageRoute(builder: (_) => const LiveWorkCameraPage()),
      );
      if (capture == null || !mounted) return;

      final position = await _getLocation();
      final originalBytes = await capture.image.readAsBytes();
      final bytes = embedGpsExifInJpeg(
        originalBytes, position, capture.capturedAt,
      );
      final address = await _resolvePhotoAddress(position, fallbackAddress: fallbackAddress);
      if (!mounted) return;
      setState(() {
        if (_editingUpdateId == null) {
          // The app now accepts one new work photo per task/member.
          _pendingPhotos
            ..clear()
            ..add(_PendingWorkPhoto(bytes: bytes,
                position: position, capturedAt: capture.capturedAt, slot: 1));
          _nextPhotoSlot = 1;
        }
        _image = capture.image;
        _imageBytes = bytes;
        _photoPosition = position;
        _capturedAt = capture.capturedAt;
        _photoAddress = address;
      });
    } catch (e) {
      if (mounted) {
        showAppMessage(context, 'Unable to capture photo: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit(Map<String, dynamic> task) async {
    if (_busy) return;
    final taskDay = _parseTaskDate(task['dateKey']);
    final today = _todayOnly();
    if (taskDay == null || taskDay.isAfter(today)) {
      showAppMessage(context, 'Future tasks cannot be updated yet.');
      return;
    }
    final overdueSubmission = taskDay.isBefore(today);
    if (overdueSubmission && _editingUpdateId != null) {
      showAppMessage(context, 'Past submissions are read-only. You may submit new evidence for an overdue task if you have not submitted work before.');
      return;
    }
    if (!hasEditWindow(task)) {
      showAppMessage(context, 'Ask admin to set workWindowStart and workWindowEnd on this task.');
      return;
    }
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      showAppMessage(context, 'Enter a short work description.');
      return;
    }
    if (_editingUpdateId == null && _pendingPhotos.length != 1) {
      showAppMessage(context, 'Capture one geo-tagged photo before saving.');
      return;
    }
    setState(() { _busy = true; _saveStage = 'Checking existing photos...'; });
    try {
      final taskRef = FirebaseFirestore.instance.collection('tasks').doc(widget.taskId);
      final existing = await taskRef.collection('workUpdates')
          .where('submittedByUid', isEqualTo: widget.currentUserUid).get()
          .timeout(const Duration(seconds: 25));
      final occupied = existing.docs.map((d) => d.id).toSet();
      final changes = <DocumentReference<Map<String, dynamic>>, Map<String, dynamic>>{};
      if (_editingUpdateId == null) {
        if (_pendingPhotos.length != 1) {
          throw StateError('Capture exactly one geo-tagged photo before saving.');
        }
        if (existing.docs.isNotEmpty) {
          throw StateError('One photo is already submitted. Retake that photo instead of adding another.');
        }
        if (occupied.contains('${widget.currentUserUid}_photo_1')) {
          throw StateError('The work photo is already saved. Reopen this task to edit it.');
        }
      } else if (!occupied.contains(_editingUpdateId)) {
        throw StateError('Existing photo not found. Reopen this task.');
      }
      _stage('Checking task permissions...');
      final latestTask = await taskRef.get().timeout(const Duration(seconds: 25));
      if (!latestTask.exists ||
          !(latestTask.data()?['assignedToUid'] is List &&
              (latestTask.data()!['assignedToUid'] as List).contains(widget.currentUserUid))) {
        throw StateError('You are no longer assigned to this task.');
      }

      final photos = _editingUpdateId == null ? List<_PendingWorkPhoto>.of(_pendingPhotos)
          : (_imageBytes == null ? <_PendingWorkPhoto>[] : [
        _PendingWorkPhoto(bytes: _imageBytes!, position: _photoPosition!,
            capturedAt: _capturedAt!, slot: _nextPhotoSlot),
      ]);
      for (var photoIndex = 0; photoIndex < photos.length; photoIndex++) {
        final photo = photos[photoIndex];
        _stage('Uploading work photo to image storage...');
        final id = _editingUpdateId ?? '${widget.currentUserUid}_photo_1';
        final updateRef = taskRef.collection('workUpdates').doc(id);
        final filename = '${id}_${DateTime.now().microsecondsSinceEpoch}.jpg';
        final path = 'task_photos/${widget.taskId}/${widget.currentUserUid}/$filename';
        final storageRef = FirebaseStorage.instance.ref(path);
        final uploadTask = storageRef.putData(photo.bytes, SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'latitude': photo.position.latitude.toString(),
            'longitude': photo.position.longitude.toString(),
            'accuracyMeters': photo.position.accuracy.toString(),
            'capturedAt': photo.capturedAt.toUtc().toIso8601String(),
            'address': _photoAddress ?? '',
            'taskId': widget.taskId,
          },
        ));
        await uploadTask.timeout(const Duration(seconds: 90));
        _stage('Getting photo ${photoIndex + 1} download URL...');
        final photoUrl = await storageRef.getDownloadURL()
            .timeout(const Duration(seconds: 25));
        changes[updateRef] = {
          'description': description,
          'photoUrl': photoUrl,
          'storagePath': path,
          'capturedAt': Timestamp.fromDate(photo.capturedAt),
          'latitude': photo.position.latitude,
          'longitude': photo.position.longitude,
          'accuracyMeters': photo.position.accuracy,
          'address': _photoAddress ?? '',
        };
      }
      if (_editingUpdateId != null && photos.isEmpty) {
        changes[taskRef.collection('workUpdates').doc(_editingUpdateId)] = {
          'description': description,
        };
      }
      _stage('Saving ${changes.length} photo record(s) in Firestore...');
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final latest = await transaction.get(taskRef);
        if (!latest.exists) throw StateError('Task no longer exists.');
        // Read all documents before any writes inside the transaction.
        final before = <DocumentReference<Map<String, dynamic>>, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final ref in changes.keys) {
          before[ref] = await transaction.get(ref);
        }
        for (final entry in changes.entries) {
          if (_editingUpdateId == null) {
            if (before[entry.key]!.exists) throw StateError('Photo slot already saved.');
            transaction.set(entry.key, {
              ...entry.value,
              'submittedByUid': widget.currentUserUid,
              'submittedAt': FieldValue.serverTimestamp(),
              'submittedOverdue': overdueSubmission,
            });
          } else {
            if (!before[entry.key]!.exists) throw StateError('Photo missing.');
            transaction.update(entry.key, {
              ...entry.value,
              'editedAt': FieldValue.serverTimestamp(),
            });
          }
        }
        if (latest.data()?['status'] == 'Pending') {
          transaction.update(taskRef, {'status': 'In Progress'});
        }
      }).timeout(const Duration(seconds: 45));
      if (!mounted) return;
      setState(() {
        _pendingPhotos.clear();
        _image = null;
        _imageBytes = null;
        _photoPosition = null;
        _capturedAt = null;
        _photoAddress = null;
        _editingUpdateId = null;
        _nextPhotoSlot = 1;
      });
      _descriptionController.clear();
      // Only leave after Firebase Storage + Firestore have acknowledged success.
      final savedCount = changes.length;
      Navigator.of(context).pop();
      debugPrint('Saved $savedCount photo work updates to Firebase.');
    } catch (e, trace) {
      debugPrint('Unable to save photos at stage: $_saveStage\n$e\n$trace');
      if (mounted) {
        showAppMessage(context, 'Save failed at $_saveStage: $e');
      }
    } finally {
      if (mounted) setState(() { _busy = false; _saveStage = ''; });
    }
  }

  void _editUpdate(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    setState(() {
      _pendingPhotos.clear();
      _editingUpdateId = doc.id;
      _descriptionController.text = (doc.data()['description'] ?? '').toString();
      _image = null;
      _imageBytes = null;
      _photoPosition = null;
      _capturedAt = null;
      _photoAddress = null;
    });
  }

  void _newUpdate([int slot = 1]) {
    setState(() {
      _editingUpdateId = null;
      _nextPhotoSlot = slot;
      // Keep other staged photos when moving to the next empty slot.
      _image = null;
      _imageBytes = null;
      _photoPosition = null;
      _capturedAt = null;
      _photoAddress = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Task Details')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('tasks').doc(widget.taskId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) return Center(child: Text('Unable to load task: ${snapshot.error}'));
            return const Center(child: CircularProgressIndicator());
          }
          final task = snapshot.data!.data();
          final assignedRaw = task?['assignedToUid'];
          final isAssigned = assignedRaw is List
              ? assignedRaw.contains(widget.currentUserUid)
              : assignedRaw == widget.currentUserUid;
          if (task == null || !isAssigned) {
            return const Center(child: Text('This task is no longer available.'));
          }
// `assignedToUid` controls task access. A trusted admin sync script
// reads /users and /municipalIds and writes task-scoped `crewMembers`.
// No private directory reads or Cloud Functions are needed in Flutter.
// Always show every assigned UID, even if the details have not been saved.
          final membersRaw = task['crewMembers'];
          final memberDetails = membersRaw is List
              ? membersRaw.whereType<Map>().toList()
              : <Map>[];
          final assignedUids = assignedRaw is List
              ? assignedRaw.whereType<String>().toList()
              : <String>[];
          final members = <Map<String, dynamic>>[];
          for (final uid in assignedUids) {
            Map? detail;
            for (final item in memberDetails) {
              if ((item['uid'] ?? item['userId'] ?? item['firebaseUid']) == uid) {
                detail = item;
                break;
              }
            }
// Older task records sometimes stored crew details without the UID.
// Don't guess which profile belongs to an assigned user: show a placeholder.
            members.add({
              'uid': uid,
              'name': detail?['name'] ?? detail?['fullName'],
              'phone': detail?['phone'] ?? detail?['phoneNumber'] ?? detail?['contact'],
              'role': detail?['role'],
            });
          }
          final status = (task['status'] ?? 'Pending').toString();
          final start = (task['startTime'] ?? '').toString();
          final end = (task['endTime'] ?? '').toString();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text((task['title'] ?? 'Clean assigned drain').toString(),
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.calendar_today_outlined, size: 18),
                const SizedBox(width: 8),
                Text(_taskDateLabel(task['dateKey'])),
              ]),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(label: Text('Shared task status: $status')),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _TaskAwardCredits(
                      taskId: widget.taskId,
                      uid: widget.currentUserUid,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('tasks')
                    .doc(widget.taskId).collection('workUpdates')
                    .where('submittedByUid', isEqualTo: widget.currentUserUid)
                    .snapshots(),
                builder: (context, uploadSnapshot) {
                  if (uploadSnapshot.hasError) {
                    return Card(child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text('Unable to read work photo: ${uploadSnapshot.error}'),
                    ));
                  }
                  final docs = uploadSnapshot.data?.docs.toList() ?? [];
                  docs.sort((a, b) {
                    final x = a.data()['submittedAt'];
                    final y = b.data()['submittedAt'];
                    return (x is Timestamp ? x.millisecondsSinceEpoch : 0)
                        .compareTo(y is Timestamp ? y.millisecondsSinceEpoch : 0);
                  });
                  final saved = docs.isEmpty ? null : docs.first;
                  final savedData = saved?.data();
                  final savedUrl = savedData?['photoUrl'];
                  final taskIsToday = isScheduledToday(task['dateKey']);
                  final taskIsOverdue = isOverdueTaskDate(task['dateKey']);
                  final canSubmitNew = saved == null && (taskIsToday || taskIsOverdue);
                  final canRetake = saved != null && taskIsToday;
                  final staged = _pendingPhotos.isNotEmpty ? _pendingPhotos.first : null;
                  return Card(child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('Work Photo',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
                        Text(staged != null ? '1 ready' : saved != null ? '1 saved' : '0 of 1',
                            style: Theme.of(context).textTheme.bodySmall),
                      ]),
                      const SizedBox(height: 12),
                      if (staged != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(staged.bytes, width: double.infinity, height: 220, fit: BoxFit.cover),
                        )
                      else if (savedUrl is String)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(savedUrl, width: double.infinity, height: 220, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(height: 140,
                                child: Center(child: Icon(Icons.broken_image_outlined, size: 40))),
                          ),
                        )
                      else
                        Container(
                          height: 130,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.add_a_photo_outlined, size: 30),
                            SizedBox(height: 6),
                            Text('No work photo captured yet'),
                          ]),
                        ),
                      if (staged != null || savedData != null) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          Icon(Icons.location_on_outlined, color: const Color(0xFF047857)),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Photo Location Details',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
                        ]),
                        const SizedBox(height: 8),
                        _GeoMetadataRow(label: 'Address', value: staged != null
                            ? (_photoAddress ?? (task['location'] ?? 'Address unavailable').toString())
                            : (savedData?['address'] ?? task['location'] ?? 'Address unavailable').toString()),
                        _GeoMetadataRow(label: 'Latitude', value: staged != null
                            ? '${staged.position.latitude.toStringAsFixed(6)}°'
                            : '${savedData?['latitude'] ?? 'Not recorded'}°'),
                        _GeoMetadataRow(label: 'Longitude', value: staged != null
                            ? '${staged.position.longitude.toStringAsFixed(6)}°'
                            : '${savedData?['longitude'] ?? 'Not recorded'}°'),
                        _GeoMetadataRow(label: 'Captured at', value: staged != null
                            ? _prettyDate(staged.capturedAt) + ' ${TimeOfDay.fromDateTime(staged.capturedAt).format(context)}'
                            : _formatCapturedAt(savedData?['capturedAt'])),
                        _GeoMetadataRow(label: 'GPS accuracy', value: staged != null
                            ? '±${staged.position.accuracy.toStringAsFixed(1)} metres'
                            : ((savedData?['accuracyMeters'] is num)
                                ? '±${(savedData!['accuracyMeters'] as num).toStringAsFixed(1)} metres'
                                : 'Not recorded')),
                        if (staged != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('GPS coordinates and capture time are embedded in this JPEG.',
                              style: Theme.of(context).textTheme.bodySmall),
                          ),
                      ],
                      const SizedBox(height: 12),
                      if (canSubmitNew || canRetake)
                        OutlinedButton.icon(
                          onPressed: _busy ? null : () async {
                            if (saved != null && taskIsToday) {
                              _editUpdate(saved);
                            } else {
                              _newUpdate(1);
                            }
                            await _takePhoto(fallbackAddress: (task['location'] ?? '').toString());
                          },
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: Text(saved != null ? 'Retake photo' : taskIsOverdue
                              ? 'Capture overdue work photo' : 'Open live camera'),
                        ),
                      if (taskIsOverdue && saved == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Overdue task: submit one new photo with current GPS details. Previously submitted work stays read-only.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFD97706))),
                        )
                      else if (!taskIsToday && saved != null)
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text('Past task: submitted photo and description are view-only.'),
                        ),
                    ]),
                  ));
                },
              ),
              if (isOverdueTaskDate(task['dateKey']))
                Builder(builder: (context) {
                  final rate = task['dailyOverdueDeduction'] is int
                      ? task['dailyOverdueDeduction'] as int : 0;
                  final day = _parseTaskDate(task['dateKey']);
                  final days = day == null ? 0 : _todayOnly().difference(day).inDays;
                  return Card(
                    color: const Color(0xFFB91C1C).withOpacity(0.06),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.warning_amber_rounded, color: const Color(0xFFB91C1C)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(rate > 0
                            ? 'Overdue warning: $days day(s) overdue. Estimated deduction: −${rate * days} credits. Final deductions are applied by the administrator.'
                            : 'Overdue warning: final credit deduction is awaiting administrator assessment.',
                          style: TextStyle(color: const Color(0xFFB91C1C), fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  );
                }),
              Card(child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  _TaskDetailRow(icon: Icons.schedule, label: 'Time',
                      value: end.isEmpty ? start : '$start – $end'),
                  const SizedBox(height: 12),
                  _TaskDetailRow(icon: Icons.location_on_outlined, label: 'Address',
                      value: (task['location'] ?? 'Not specified').toString()),
                  const SizedBox(height: 12),
                  _TaskDetailRow(icon: Icons.notes, label: 'Instructions',
                      value: (task['description'] ?? 'Not specified').toString()),
                ]),
              )),
              const SizedBox(height: 16),
              Text('Assigned Crew Members', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              if (members.isEmpty)
                const Padding(padding: EdgeInsets.all(12),
                    child: Text('No crew members are assigned to this task.')),
              for (final member in members)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                  title: Text(
                    (member['name']?.toString().trim().isNotEmpty ?? false)
                        ? member['name'].toString()
                        : member['uid'] == widget.currentUserUid
                        ? 'You (crew details missing)'
                        : 'Assigned crew member (details missing)',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((member['role'] ?? 'Crew Member').toString()),
                      Text('Contact: ${member['phone']?.toString().trim().isNotEmpty == true ? member['phone'] : 'Not provided'}'),
                      if (member['uid'] == widget.currentUserUid)
                        const Text('You are assigned to this task.'),
                    ],
                  ),
                ),
              if (members.any((member) => member['name'] == null ||
                  member['name'] == 'Crew member'))
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text('Crew details have not been synced yet. Ask the administrator to run the task crew sync script.'),
                ),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('tasks')
                    .doc(widget.taskId).collection('workUpdates')
                    .where('submittedByUid', isEqualTo: widget.currentUserUid)
                    .snapshots(),
                builder: (context, savedUpdatesSnapshot) {
                  if (!savedUpdatesSnapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  final isTodayTask = isScheduledToday(task['dateKey']);
                  final isOverdueTask = isOverdueTaskDate(task['dateKey']);
                  final hasPriorSubmission = savedUpdatesSnapshot.data!.docs.isNotEmpty;
                  final allowOverdueSubmission = isOverdueTask && !hasPriorSubmission;
                  if (!isTodayTask && !allowOverdueSubmission) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('This past task is view-only. Overdue tasks can accept new evidence only if you have not submitted work for them before.'),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      Text('Work Description', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(controller: _descriptionController,
                          maxLines: 3, maxLength: 500,
                          decoration: const InputDecoration(hintText: 'Describe your work...')),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _submit(task),
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: Text(_busy ? 'Saving...' :
                            _editingUpdateId == null ? 'Save Photo & Work Update' : 'Save Changes'),
                      ),
                      if (_busy && _saveStage.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 6),
                        Text(_saveStage, textAlign: TextAlign.center),
                      ],
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Camera capture includes the time when the shutter was pressed.
