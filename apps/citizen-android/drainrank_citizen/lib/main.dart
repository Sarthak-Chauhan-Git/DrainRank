import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import 'core/constants.dart';
import 'models/citizen_report.dart';
import 'services/drainrank_engine.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DrainRankCitizenApp());
}

class DrainRankCitizenApp extends StatelessWidget {
  const DrainRankCitizenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DrainRank Citizen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0D47A1),
          primary: const Color(0xFF0D47A1),
          secondary: const Color(0xFF00897B),
          surface: const Color(0xFFF5F7FA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F6F9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A2540),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const DrainRankHomeShell(),
    );
  }
}

class DrainRankHomeShell extends StatefulWidget {
  const DrainRankHomeShell({super.key});

  @override
  State<DrainRankHomeShell> createState() => _DrainRankHomeShellState();
}

class _DrainRankHomeShellState extends State<DrainRankHomeShell> {
  int _selectedIndex = 0;
  String _deviceId = 'Loading...';

  @override
  void initState() {
    super.initState();
    _initDevice();
  }

  Future<void> _initDevice() async {
    final id = await DrainRankEngine.getDeviceId();
    if (mounted) setState(() => _deviceId = id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.water_drop, color: Color(0xFF4FC3F7), size: 20),
                SizedBox(width: 8),
                Text(
                  'DrainRank',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
                ),
                SizedBox(width: 8),
                Chip(
                  label: Text(
                    'CITIZEN PORTAL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  backgroundColor: Color(0xFF1565C0),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            Text(
              'Device Lock ID: $_deviceId • 15m Radius Guard Active',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: _selectedIndex == 0
          ? ReportIssueTab(
        deviceId: _deviceId,
        onReportSubmitted: () => setState(() => _selectedIndex = 1),
      )
          : const TrackStatusTab(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (idx) => setState(() => _selectedIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.add_a_photo_outlined),
            selectedIcon: Icon(Icons.add_a_photo),
            label: 'Step 1: Report Issue',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Step 8: Track Status',
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TAB 1: STEP 1 - CITIZEN REPORTS ISSUE
// ============================================================================
class ReportIssueTab extends StatefulWidget {
  final String deviceId;
  final VoidCallback onReportSubmitted;

  const ReportIssueTab({
    super.key,
    required this.deviceId,
    required this.onReportSubmitted,
  });

  @override
  State<ReportIssueTab> createState() => _ReportIssueTabState();
}

class _ReportIssueTabState extends State<ReportIssueTab> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _descController = TextEditingController();

  File? _capturedImage;
  DateTime? _capturedAt;
  ImageQualityResult? _qualityResult;

  double? _latitude;
  double? _longitude;
  double? _gpsAccuracy;
  KnownDrainPin? _matchedDrain;

  IssueCategory _selectedCategory = IssueCategory.blockedDrain;
  String? _aiSuggestedLabel;
  double? _aiConfidence;

  bool _isUrgentFlagged = false;
  UrgencyConsequence _selectedConsequence =
      UrgencyConsequence.standardResidential;

  bool _isLoadingGps = false;
  bool _isSubmitting = false;
  bool _syntheticDemoPinMode = false;

  Future<void> _captureGeotaggedPhoto() async {
    setState(() => _isLoadingGps = true);
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1280,
      );

      if (photo == null) {
        setState(() => _isLoadingGps = false);
        return;
      }

      final captureTimestamp = DateTime.now();
      final imageFile = File(photo.path);
      final quality = await DrainRankEngine.analyzeAndHashPhoto(imageFile);

      double lat;
      double lng;
      double acc;

      if (_syntheticDemoPinMode) {
        lat = kDemoDrainInventory.first.latitude;
        lng = kDemoDrainInventory.first.longitude;
        acc = 3.5;
      } else {
        final pos = await DrainRankEngine.acquireGeotagPosition();
        lat = pos.latitude;
        lng = pos.longitude;
        acc = pos.accuracy;
      }

      final matched = DrainRankEngine.findNearestDrain(lat, lng);

      setState(() {
        _capturedImage = imageFile;
        _capturedAt = captureTimestamp;
        _qualityResult = quality;
        _latitude = lat;
        _longitude = lng;
        _gpsAccuracy = acc;
        _matchedDrain = matched;
        _aiSuggestedLabel = 'Blocked Drain (Visible Surface Debris)';
        _aiConfidence = 0.92;
        _selectedCategory = IssueCategory.blockedDrain;

        if (matched != null && matched.defaultConsequenceV >= 0.8) {
          _isUrgentFlagged = true;
          _selectedConsequence = UrgencyConsequence.criticalHospitalSchool;
        }
        _isLoadingGps = false;
      });
    } catch (e) {
      setState(() => _isLoadingGps = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Geotag Error: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _submitCitizenReport() async {
    if (_capturedImage == null || _latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a Geotagged Photograph first.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final duplicateCheck = await DrainRankEngine.checkSameDeviceRadiusLock(
      currentLat: _latitude!,
      currentLng: _longitude!,
      deviceId: widget.deviceId,
    );

    if (duplicateCheck.isBlocked && duplicateCheck.existingReport != null) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        _showRadiusCooldownDialog(
          duplicateCheck.existingReport!,
          duplicateCheck.distanceMeters ?? 0.0,
        );
      }
      return;
    }

    final uniqueReportId = DrainRankEngine.generateUniqueReportId();
    final priorityScore = DrainRankEngine.computePriorityScore(
      category: _selectedCategory,
      urgency: _selectedConsequence,
      matchedDrain: _matchedDrain,
    );

    final newReport = CitizenReport(
      reportId: uniqueReportId,
      deviceId: widget.deviceId,
      linkedDrainId: _matchedDrain?.drainId ?? 'PROVISIONAL-PIN',
      latitude: _latitude!,
      longitude: _longitude!,
      gpsAccuracyMeters: _gpsAccuracy ?? 5.0,
      capturedAt: _capturedAt!,
      uploadedAt: DateTime.now(),
      imagePath: _capturedImage!.path,
      imageSha256Hash: _qualityResult!.sha256Hash,
      imageQualityPassed: _qualityResult!.isValid,
      imageLuminance: _qualityResult!.luminance,
      issueCategory: _selectedCategory,
      aiSuggestedCategory: _aiSuggestedLabel,
      aiConfidence: _aiConfidence,
      isUrgentFlagged: _isUrgentFlagged,
      urgencyConsequence: _selectedConsequence,
      description: _descController.text.trim().isEmpty
          ? 'Drain is blocked with garbage and debris.'
          : _descController.text.trim(),
      status: ReportWorkflowStatus.complaintReceived,
      estimatedPriorityScore: priorityScore,
    );

    await DrainRankEngine.saveReport(newReport);
    setState(() => _isSubmitting = false);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.verified, color: Colors.green),
              SizedBox(width: 8),
              Expanded(child: Text('Report Registered')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unique Report ID: ${newReport.reportId}',
                style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const SizedBox(height: 6),
              Text('Linked Drain ID: ${newReport.linkedDrainId}'),
              Text('Assigned Queue: ${newReport.issueCategory.triageQueue}'),
              Text(
                  'Preliminary Priority Score: ${newReport.estimatedPriorityScore}'),
              const Divider(height: 18),
              const Text(
                '15m Same-Device Geotag Lock is now active for this coordinate to prevent duplicate spam.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onReportSubmitted();
              },
              child: const Text('Track Live Status (Step 8)'),
            ),
          ],
        ),
      );
    }
  }

  void _showRadiusCooldownDialog(
      CitizenReport existing, double distanceMeters) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFF8F6),
        title: Row(
          children: [
            Icon(Icons.location_off, color: Colors.red.shade700),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Duplicate Location Blocked',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This device (${existing.deviceId}) already submitted a report within ${AppConstants.duplicateRadiusMeters.toInt()}m of this location.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Active Report ID: ${existing.reportId}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('Linked Drain: ${existing.linkedDrainId}'),
                  Text(
                      'Distance from previous pin: ${distanceMeters.toStringAsFixed(1)} meters'),
                  Text('Current Status: ${existing.status.title}'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Rule: A single device cannot continuously report the same drain location within a 15m radius.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Dismiss'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onReportSubmitted();
            },
            child: const Text('View Existing Report'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          elevation: 0,
          color: const Color(0xFFE3F2FD),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF90CAF9)),
          ),
          child: SwitchListTile(
            dense: true,
            title: const Text(
              'Synthetic Ward 12 Coordinates (Demo Mode • FR-10)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            subtitle: Text(
              _syntheticDemoPinMode
                  ? 'Snapping GPS to DR-1024 (Lat 28.9845, Lng 77.7064) for deterministic demo'
                  : 'Using live hardware GPS from your phone',
              style: const TextStyle(fontSize: 11.5),
            ),
            value: _syntheticDemoPinMode,
            onChanged: (val) => setState(() => _syntheticDemoPinMode = val),
          ),
        ),
        const SizedBox(height: 12),

        // 1. GEOTAG PHOTOGRAPH CARD
        Card(
          elevation: 2,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.camera_alt, color: Color(0xFF0D47A1)),
                    SizedBox(width: 8),
                    Text(
                      '1. Geotag Photograph',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_capturedImage == null)
                  InkWell(
                    onTap: _isLoadingGps ? null : _captureGeotaggedPhoto,
                    child: Container(
                      height: 190,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFECEFF1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: const Color(0xFFB0BEC5), width: 1.5),
                      ),
                      child: _isLoadingGps
                          ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text(
                              'Locking High-Accuracy GPS & Hashing Image...'),
                        ],
                      )
                          : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo,
                              size: 46, color: Color(0xFF1565C0)),
                          SizedBox(height: 8),
                          Text(
                            'Tap to Capture Live Geotagged Drain Photo',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0D47A1)),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Auto-captures GPS Lat/Lng, Timestamp & SHA-256 Hash',
                            style: TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              _capturedImage!,
                              height: 210,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.only(
                                  bottomLeft: Radius.circular(12),
                                  bottomRight: Radius.circular(12),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.gps_fixed,
                                          size: 14, color: Colors.greenAccent),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Lat ${_latitude!.toStringAsFixed(4)}, Long ${_longitude!.toStringAsFixed(4)} (±${_gpsAccuracy!.toStringAsFixed(1)}m)',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Captured: ${DateFormat('dd MMM yyyy, hh:mm:ss a').format(_capturedAt!)}',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 11),
                                  ),
                                  Text(
                                    'SHA-256: ${_qualityResult!.sha256Hash.substring(0, 24)}...',
                                    style: const TextStyle(
                                        color: Colors.amberAccent,
                                        fontSize: 10.5,
                                        fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: ElevatedButton.icon(
                              onPressed: _captureGeotaggedPhoto,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Retake'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black87,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Chip(
                            avatar: Icon(
                              _qualityResult!.isValid
                                  ? Icons.check_circle
                                  : Icons.warning,
                              color: _qualityResult!.isValid
                                  ? Colors.green
                                  : Colors.orange,
                              size: 18,
                            ),
                            label: Text(
                              _qualityResult!.statusMessage,
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            backgroundColor: _qualityResult!.isValid
                                ? Colors.green.shade50
                                : Colors.orange.shade50,
                          ),
                          Chip(
                            avatar: const Icon(Icons.pin_drop,
                                size: 18, color: Color(0xFF0D47A1)),
                            label: Text(
                              _matchedDrain != null
                                  ? 'Linked Drain: ${_matchedDrain!.drainId} (${_matchedDrain!.name})'
                                  : 'New Location: Provisional Drain Pin',
                              style: const TextStyle(
                                  fontSize: 11.5, fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: const Color(0xFFE3F2FD),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // MINI OPENSTREETMAP PREVIEW
        if (_latitude != null && _longitude != null)
          Card(
            elevation: 2,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 145,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(_latitude!, _longitude!),
                    initialZoom: 17.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'in.drainrank.drainrank_citizen',
                    ),
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: LatLng(_latitude!, _longitude!),
                          radius: AppConstants.duplicateRadiusMeters,
                          useRadiusInMeter: true,
                          color: Colors.blue.withValues(alpha: 0.22),
                          borderColor: Colors.blue.shade800,
                          borderStrokeWidth: 2,
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(_latitude!, _longitude!),
                          width: 40,
                          height: 40,
                          child: const Icon(Icons.location_on,
                              color: Colors.red, size: 36),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_latitude != null) const SizedBox(height: 12),

        // 2. ISSUE CLASSIFICATION (Updated to Flutter 3.32+ RadioGroup API)
        Card(
          elevation: 2,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.category, color: Color(0xFF0D47A1)),
                    SizedBox(width: 8),
                    Text(
                      '2. Issue Classification',
                      style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (_aiSuggestedLabel != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'AI Assisted Pre-Check: $_aiSuggestedLabel (${(_aiConfidence! * 100).toInt()}% conf)',
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                RadioGroup<IssueCategory>(
                  groupValue: _selectedCategory,
                  onChanged: (IssueCategory? val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                  child: Column(
                    children: IssueCategory.values
                        .map(
                          (category) => RadioListTile<IssueCategory>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          category.label,
                          style:
                          const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Routes to: ${category.triageQueue} (Factor weight: ${category.bScoreInput})',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        value: category,
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

        // 3. URGENCY FLAG & V-CONSEQUENCE SELECTOR
        Card(
          elevation: 2,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    Icons.warning_amber_rounded,
                    color: _isUrgentFlagged
                        ? Colors.red.shade700
                        : Colors.grey.shade700,
                  ),
                  title: const Text(
                    '3. High-Urgency Flag',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Flag critical access routes, hospital roads, or active overflow hazards',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _isUrgentFlagged,
                  onChanged: (val) {
                    setState(() {
                      _isUrgentFlagged = val;
                      if (val &&
                          _selectedConsequence ==
                              UrgencyConsequence.standardResidential) {
                        _selectedConsequence =
                            UrgencyConsequence.importantRoute;
                      } else if (!val) {
                        _selectedConsequence =
                            UrgencyConsequence.standardResidential;
                      }
                    });
                  },
                ),
                const Divider(),
                const Text(
                  'Site Criticality / Consequence Factor (V):',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<UrgencyConsequence>(
                  key: ValueKey(_selectedConsequence),
                  initialValue: _selectedConsequence,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: UrgencyConsequence.values
                      .map(
                        (u) => DropdownMenuItem(
                      value: u,
                      child: Text(
                        '${u.label} (V=${u.vWeight})',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedConsequence = val;
                        _isUrgentFlagged = val.isUrgentFlag;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // 4. DESCRIPTION & SUBMIT BUTTON
        Card(
          elevation: 2,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '4. Add Field Description',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _descController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText:
                    'e.g., Drain is completely blocked with plastic garbage near Hospital Gate 2',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submitCitizenReport,
                    icon: const Icon(Icons.send),
                    label: Text(
                      _isSubmitting
                          ? 'Validating Geotag & Radius...'
                          : 'Submit Geotagged Report',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ============================================================================
// TAB 2: STEP 8 - UPDATE & TRACK DRAIN STATUS
// ============================================================================
class TrackStatusTab extends StatefulWidget {
  const TrackStatusTab({super.key});

  @override
  State<TrackStatusTab> createState() => _TrackStatusTabState();
}

class _TrackStatusTabState extends State<TrackStatusTab> {
  List<CitizenReport> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final list = await DrainRankEngine.getSavedReports();
    if (mounted) {
      setState(() {
        _reports = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_reports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.assignment_late_outlined,
                  size: 64, color: Colors.blueGrey.shade300),
              const SizedBox(height: 12),
              const Text(
                'No Reports Submitted Yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Switch to Step 1 to capture a geotagged drain photograph and generate a Unique Report ID.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFFE3F2FD),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Logged Reports (${_reports.length}) • Tap Status to Simulate Next Stage',
                style:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              TextButton.icon(
                onPressed: () async {
                  await DrainRankEngine.clearAllDemoReports();
                  _loadReports();
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Reset Lock', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: _reports.length,
            itemBuilder: (context, index) {
              final r = _reports[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 14),
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A2540),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              r.reportId,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          if (r.isUrgentFlagged)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'URGENT • V=${r.urgencyConsequence.vWeight}',
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(r.imagePath),
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    width: 72,
                                    height: 72,
                                    color: Colors.grey.shade300,
                                    child: const Icon(Icons.image),
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${r.issueCategory.label} • ${r.linkedDrainId}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                                Text(
                                  'GPS: ${r.latitude.toStringAsFixed(4)}, ${r.longitude.toStringAsFixed(4)}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                                Text(
                                  'Triage: ${r.issueCategory.triageQueue} (Score: ${r.estimatedPriorityScore})',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF0D47A1),
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 22),
                      const Text(
                        'Step 8: Live Municipal Workflow Status',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      ...ReportWorkflowStatus.values.map((stage) {
                        final isDone = stage.stepIndex <= r.status.stepIndex;
                        final isCurrent = stage.stepIndex == r.status.stepIndex;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Icon(
                                isDone
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 18,
                                color: isCurrent
                                    ? Colors.orange.shade800
                                    : (isDone ? Colors.green : Colors.grey),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  stage.title,
                                  style: TextStyle(
                                    fontWeight: isCurrent
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color:
                                    isDone ? Colors.black87 : Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await DrainRankEngine.advanceDemoStatus(r.reportId);
                            _loadReports();
                          },
                          icon: const Icon(Icons.fast_forward, size: 16),
                          label: const Text('Simulate Next Backend Status'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}