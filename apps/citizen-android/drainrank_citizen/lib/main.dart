import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants.dart';
import 'models/citizen_report.dart';
import 'services/drainrank_engine.dart';
import 'services/high_urgency_places_service.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isEmpty || _supabasePublishableKey.isEmpty) {
    runApp(const _BackendSetupRequiredApp());
    return;
  }
  await Supabase.initialize(
    url: _supabaseUrl,
    publishableKey: _supabasePublishableKey,
  );
  runApp(const DrainRankCitizenApp());
}

class _BackendSetupRequiredApp extends StatelessWidget {
  const _BackendSetupRequiredApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Supabase is not configured. Run this app with '
            '--dart-define=SUPABASE_URL=... and '
            '--dart-define=SUPABASE_PUBLISHABLE_KEY=... .',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
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
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
          primary: const Color(0xFF0F766E),
          secondary: const Color(0xFF14B8A6),
          surface: const Color(0xFFFFFFFF),
          error: const Color(0xFFB91C1C),
        ),

        scaffoldBackgroundColor: const Color(0xFFF8FAFC),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
        ),

        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFD8E4E8)),
          ),
        ),

        dividerTheme: const DividerThemeData(
          color: Color(0xFFE7EEF0),
          thickness: 1,
          space: 1,
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD8E4E8)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD8E4E8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.5),
          ),
        ),

        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),

      home: const CitizenAuthGate(),
    );
  }
}

class CitizenAuthGate extends StatefulWidget {
  const CitizenAuthGate({super.key});

  @override
  State<CitizenAuthGate> createState() => _CitizenAuthGateState();
}

class _CitizenAuthGateState extends State<CitizenAuthGate> {
  late final StreamSubscription<AuthState> _authSubscription;
  bool _signedIn = Supabase.instance.client.auth.currentSession != null;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((
      state,
    ) {
      if (mounted) setState(() => _signedIn = state.session != null);
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _signedIn ? const DrainRankHomeShell() : const CitizenEmailAuthPage();
}

enum _AuthMode { signIn, signUp }

class CitizenEmailAuthPage extends StatefulWidget {
  const CitizenEmailAuthPage({super.key});

  @override
  State<CitizenEmailAuthPage> createState() => _CitizenEmailAuthPageState();
}

class _CitizenEmailAuthPageState extends State<CitizenEmailAuthPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_mode == _AuthMode.signUp) {
        final response = await auth.signUp(email: email, password: password);
        if (mounted && response.session == null) {
          setState(
            () => _error =
                'Account created. Check your email to confirm it, then sign in.',
          );
        }
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not sign in: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.water_drop_rounded,
                      size: 48,
                      color: Color(0xFF0F766E),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _mode == _AuthMode.signUp
                          ? 'Create your citizen account'
                          : 'Citizen sign in',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sign in to submit reports and track their municipal status.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    SegmentedButton<_AuthMode>(
                      segments: const [
                        ButtonSegment(
                          value: _AuthMode.signIn,
                          label: Text('Sign in'),
                        ),
                        ButtonSegment(
                          value: _AuthMode.signUp,
                          label: Text('Create account'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) => setState(() {
                              _mode = selection.first;
                              _error = null;
                            }),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      enabled: !_busy,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _authenticate(),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _authenticate,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _mode == _AuthMode.signUp
                                  ? 'Create account'
                                  : 'Sign in',
                            ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Use a confirmed email account. New accounts may need '
                      'email confirmation, depending on the Supabase project settings.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
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
        toolbarHeight: 82,
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F766E), Color(0xFF14B8A6)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.water_drop_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'DrainRank',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Cleaner Drains, Safer Cities',
              style: TextStyle(
                fontSize: 11,
                color: Color(0xFFCBD5E1),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('You are all caught up.')),
              );
            },
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'Profile menu',
            icon: const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFCCFBF1),
              child: Icon(
                Icons.person_outline_rounded,
                color: Color(0xFF0F766E),
                size: 21,
              ),
            ),
            onSelected: (value) async {
              if (value == 'My Reports') {
                setState(() => _selectedIndex = 1);
                return;
              }

              if (value == 'Sign Out') {
                try {
                  await Supabase.instance.client.auth.signOut();
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not sign out: $error')),
                  );
                }
                return;
              }

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DrainRankUtilityPage(title: value),
                ),
              );
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'My Reports',
                child: ListTile(
                  leading: Icon(Icons.assignment_outlined),
                  title: Text('My Reports'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'Saved Locations',
                child: ListTile(
                  leading: Icon(Icons.location_on_outlined),
                  title: Text('Saved Locations'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'Settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'Help & Support',
                child: ListTile(
                  leading: Icon(Icons.help_outline_rounded),
                  title: Text('Help & Support'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'About DrainRank',
                child: ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('About DrainRank'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'Sign Out',
                child: ListTile(
                  leading: Icon(Icons.logout_rounded),
                  title: Text('Sign Out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
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
            selectedIcon: Icon(Icons.add_a_photo_rounded),
            label: 'Report Issue',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: 'Track Status',
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

  bool _isCheckingUrgency = false;
  bool _urgencyLocationVerified = false;
  String? _urgencyVerificationMessage;

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
        _urgencyLocationVerified = false;
        _urgencyVerificationMessage = null;
        _isUrgentFlagged = false;
        _selectedConsequence = UrgencyConsequence.standardResidential;
        _matchedDrain = matched;
        _aiSuggestedLabel = null;
        _aiConfidence = null;
        _selectedCategory = IssueCategory.blockedDrain;

        _isUrgentFlagged = false;
        _selectedConsequence = UrgencyConsequence.standardResidential;
        _isLoadingGps = false;
      });
      await _verifyHighUrgencyLocation();
    } catch (e) {
      debugPrint('High urgency lookup failed: $e');
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

  Future<void> _verifyHighUrgencyLocation() async {
    if (_isCheckingUrgency) return;

    // Use the coordinates associated with the current report.
    final latitude = _latitude;
    final longitude = _longitude;

    if (latitude == null || longitude == null) {
      setState(() {
        _urgencyLocationVerified = false;
        _isUrgentFlagged = false;
        _selectedConsequence = UrgencyConsequence.standardResidential;
        _urgencyVerificationMessage =
            'Capture a geotagged photo before verifying.';
      });
      return;
    }

    setState(() {
      _isCheckingUrgency = true;
      _urgencyLocationVerified = false;
      _urgencyVerificationMessage =
          'Checking for nearby high-urgency facilities within 500 m...';
    });

    try {
      final places = await HighUrgencyPlacesService().fetchNearbyPlaces(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: 500,
      );

      // Confirm the facility is actually within the required radius.
      final nearbyPlaces = places.where((place) {
        return HighUrgencyPlacesService().isWithinUrgencyRadius(
          reportLatitude: latitude,
          reportLongitude: longitude,
          place: place,
          radiusMeters: 500,
        );
      }).toList();

      if (!mounted) return;

      if (nearbyPlaces.isEmpty) {
        setState(() {
          _urgencyLocationVerified = false;
          _isUrgentFlagged = false;
          _selectedConsequence = UrgencyConsequence.standardResidential;
          _urgencyVerificationMessage =
              'No matching high-urgency facilities found within 500 m.';
        });
        return;
      }

      final place = nearbyPlaces.first;
      final distance = Geolocator.distanceBetween(
        latitude,
        longitude,
        place.latitude,
        place.longitude,
      );

      setState(() {
        _urgencyLocationVerified = true;
        _isUrgentFlagged = true;
        _selectedConsequence = UrgencyConsequence.criticalHospitalSchool;
        _urgencyVerificationMessage =
            '${place.name} (${place.type}) verified '
            '${distance.round()} m from report location.';
      });
    } catch (e, stackTrace) {
      debugPrint('URGENT FACILITY VERIFICATION ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _urgencyLocationVerified = false;
        _isUrgentFlagged = false;
        _selectedConsequence = UrgencyConsequence.standardResidential;
        _urgencyVerificationMessage = 'Verification failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingUrgency = false;
        });
      }
    }
  }

  Future<void> _submitCitizenReport() async {
    if (_isUrgentFlagged && !_urgencyLocationVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'High urgency requires verified hospital or school '
            'within 500 metres of the report location.',
          ),
        ),
      );
      return;
    }
    if (_capturedImage == null || _latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please capture a Geotagged Photograph first.'),
        ),
      );
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in before submitting a report.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    late final CitizenReport newReport;
    String? uploadedPhotoPath;
    try {
      final duplicateCheck = await DrainRankEngine.checkSameDeviceRadiusLock(
        currentLat: _latitude!,
        currentLng: _longitude!,
        deviceId: widget.deviceId,
        userId: user.id,
      );
      if (duplicateCheck.isBlocked && duplicateCheck.existingReport != null) {
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
      final uploadedAt = DateTime.now();
      uploadedPhotoPath = '${user.id}/$uniqueReportId.jpg';
      final photoBytes = await _capturedImage!.readAsBytes();
      await Supabase.instance.client.storage
          .from('citizen-photos')
          .uploadBinary(
            uploadedPhotoPath,
            photoBytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );

      newReport = CitizenReport(
        reportId: uniqueReportId,
        deviceId: widget.deviceId,
        linkedDrainId: _matchedDrain?.drainId ?? 'PROVISIONAL-PIN',
        latitude: _latitude!,
        longitude: _longitude!,
        gpsAccuracyMeters: _gpsAccuracy ?? 5.0,
        capturedAt: _capturedAt!,
        uploadedAt: uploadedAt,
        imagePath: uploadedPhotoPath,
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
      await Supabase.instance.client.from('citizen_reports').insert({
        'report_id': newReport.reportId,
        'reporter_id': user.id,
        'device_id': newReport.deviceId,
        'linked_drain_id': newReport.linkedDrainId,
        'latitude': newReport.latitude,
        'longitude': newReport.longitude,
        'captured_at': newReport.capturedAt.toUtc().toIso8601String(),
        'uploaded_at': uploadedAt.toUtc().toIso8601String(),
        'image_path': uploadedPhotoPath,
        'image_sha256_hash': newReport.imageSha256Hash,
        'image_url': null,
        'issue_category': newReport.issueCategory.name,
        'is_urgent_flagged': newReport.isUrgentFlagged,
        'urgency_consequence': newReport.urgencyConsequence.name,
        'description': newReport.description,
        'status': 'complaint_received',
        'estimated_priority_score': newReport.estimatedPriorityScore,
        'payload': {
          'gps_accuracy_meters': newReport.gpsAccuracyMeters,
          'image_quality_passed': newReport.imageQualityPassed,
          'image_luminance': newReport.imageLuminance,
          'ai_suggested_category': newReport.aiSuggestedCategory,
          'ai_confidence': newReport.aiConfidence,
          'urgency_consequence_label': newReport.urgencyConsequence.label,
        },
      });
      try {
        await DrainRankEngine.saveReport(newReport, userId: user.id);
      } catch (cacheError) {
        debugPrint('Could not cache submitted report locally: $cacheError');
      }
    } catch (error) {
      if (uploadedPhotoPath != null) {
        try {
          await Supabase.instance.client.storage.from('citizen-photos').remove([
            uploadedPhotoPath,
          ]);
        } catch (cleanupError) {
          debugPrint('Could not remove orphaned report photo: $cleanupError');
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit report: $error')),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }

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
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text('Linked Drain ID: ${newReport.linkedDrainId}'),
              Text('Assigned Queue: ${newReport.issueCategory.triageQueue}'),
              Text(
                'Preliminary Priority Score: ${newReport.estimatedPriorityScore}',
              ),
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
    CitizenReport existing,
    double distanceMeters,
  ) {
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
                  Text(
                    'Active Report ID: ${existing.reportId}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('Linked Drain: ${existing.linkedDrainId}'),
                  Text(
                    'Distance from previous pin: ${distanceMeters.toStringAsFixed(1)} meters',
                  ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Icon(Icons.camera_alt, color: Color(0xFF0D47A1)),
                    Text(
                      '1. Geotag Photograph',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_capturedImage == null)
                  InkWell(
                    onTap: _isLoadingGps ? null : _captureGeotaggedPhoto,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 190),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFECEFF1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFB0BEC5),
                          width: 1.5,
                        ),
                      ),
                      child: _isLoadingGps
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text(
                                  'Locking High-Accuracy GPS & Hashing Image...',
                                ),
                              ],
                            )
                          : const Padding(
                              padding: EdgeInsets.all(12),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.add_a_photo,
                                    size: 46,
                                    color: Color(0xFF1565C0),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Tap to Capture Live Geotagged Drain Photo',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0D47A1),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Auto-captures GPS Lat/Lng, Timestamp & SHA-256 Hash',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
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
                                      const Icon(
                                        Icons.gps_fixed,
                                        size: 14,
                                        color: Colors.greenAccent,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'Lat ${_latitude!.toStringAsFixed(4)}, Long ${_longitude!.toStringAsFixed(4)} (±${_gpsAccuracy!.toStringAsFixed(1)}m)',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Captured: ${DateFormat('dd MMM yyyy, hh:mm:ss a').format(_capturedAt!)}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                  Text(
                                    'SHA-256: ${_qualityResult!.sha256Hash.substring(0, 24)}...',
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 10.5,
                                      fontFamily: 'monospace',
                                    ),
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
                            avatar: const Icon(
                              Icons.pin_drop,
                              size: 18,
                              color: Color(0xFF0D47A1),
                            ),
                            label: Text(
                              _matchedDrain != null
                                  ? 'Linked Drain: ${_matchedDrain!.drainId} (${_matchedDrain!.name})'
                                  : 'New Location: Provisional Drain Pin',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
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
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 36,
                          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Icon(Icons.category, color: Color(0xFF0D47A1)),
                    Text(
                      '2. Issue Classification',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (_aiSuggestedLabel != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFFB45309)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'AI classification is not available yet. '
                            'Please select the issue category manually.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 8),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: _isUrgentFlagged
                            ? Colors.red.shade700
                            : Colors.grey.shade700,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '3. High-Urgency Flag',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'Flag critical access routes, hospital roads, or active overflow hazards',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isUrgentFlagged,
                      onChanged: (val) {
                        if (val && !_urgencyLocationVerified) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Verify nearby facilities before enabling high urgency.',
                              ),
                            ),
                          );
                          return;
                        }

                        setState(() {
                          _isUrgentFlagged = val;

                          _selectedConsequence = val
                              ? UrgencyConsequence.criticalHospitalSchool
                              : UrgencyConsequence.standardResidential;
                        });
                      },
                    ),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isCheckingUrgency
                              ? null
                              : _verifyHighUrgencyLocation,
                          icon: _isCheckingUrgency
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.location_searching),
                          label: Text(
                            _isCheckingUrgency
                                ? 'Checking nearby hospitals and schools...'
                                : 'Verify hospital / school within 500 m',
                          ),
                        ),
                      ),
                      if (_urgencyVerificationMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _urgencyLocationVerified
                                    ? Icons.verified
                                    : Icons.info_outline,
                                size: 16,
                                color: _urgencyLocationVerified
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _urgencyVerificationMessage!,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                const Divider(),
                const Text(
                  'Site Criticality / Consequence Factor (V):',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<UrgencyConsequence>(
                  isExpanded: true,
                  key: ValueKey(_selectedConsequence),
                  initialValue: _selectedConsequence,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: UrgencyConsequence.values
                      .map(
                        (u) => DropdownMenuItem(
                          value: u,
                          child: Text(
                            '${u.label} (V=${u.vWeight})',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedConsequence = val;

                        // Choosing a consequence alone must not verify high urgency.
                        if (val == UrgencyConsequence.standardResidential) {
                          _isUrgentFlagged = false;
                        }
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _reports = [];
          _loadError = 'Sign in to view your reports.';
          _loading = false;
        });
      }
      return;
    }
    try {
      final rows = await client
          .from('citizen_reports')
          .select()
          .eq('reporter_id', user.id)
          .order('created_at', ascending: false);
      final list = <CitizenReport>[];
      for (final row in rows) {
        final imagePath = row['image_path'] as String?;
        final imageUrl = imagePath == null
            ? null
            : await client.storage
                  .from('citizen-photos')
                  .createSignedUrl(imagePath, 3600);
        list.add(_citizenReportFromRow(row, imageUrl));
      }
      String? cacheWarning;
      try {
        await DrainRankEngine.cacheReports(list, userId: user.id);
      } catch (error) {
        cacheWarning =
            'Reports loaded, but the offline cache could not update: $error';
      }
      if (mounted) {
        setState(() {
          _reports = list;
          _loadError = cacheWarning;
          _loading = false;
        });
      }
    } catch (error) {
      var cached = <CitizenReport>[];
      String? cacheError;
      try {
        cached = await DrainRankEngine.getSavedReports(userId: user.id);
      } catch (error) {
        cacheError = error.toString();
      }
      if (mounted) {
        setState(() {
          _reports = cached;
          _loadError = [
            'Could not refresh reports from Supabase: $error',
            if (cacheError != null)
              'Could not read the local report cache: $cacheError',
          ].join('\n');
          _loading = false;
        });
      }
    }
  }

  CitizenReport _citizenReportFromRow(
    Map<String, dynamic> row,
    String? imageUrl,
  ) {
    final rawStatus = (row['status'] as String? ?? 'complaint_received')
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    final workflowStatus = switch (rawStatus) {
      'under_verification' => ReportWorkflowStatus.underVerification,
      'work_assigned' || 'assigned' => ReportWorkflowStatus.workAssigned,
      'cleaning_completed' ||
      'resolved' => ReportWorkflowStatus.cleaningCompleted,
      'under_monitoring' ||
      'monitoring' => ReportWorkflowStatus.underMonitoring,
      _ => ReportWorkflowStatus.complaintReceived,
    };
    return CitizenReport(
      reportId: row['report_id'] as String,
      deviceId: row['device_id'] as String? ?? '',
      linkedDrainId: row['linked_drain_id'] as String? ?? 'Unassigned',
      latitude: (row['latitude'] as num).toDouble(),
      longitude: (row['longitude'] as num).toDouble(),
      gpsAccuracyMeters:
          ((row['payload'] as Map<String, dynamic>?)?['gps_accuracy_meters']
                  as num?)
              ?.toDouble() ??
          0,
      capturedAt: DateTime.parse(row['captured_at'] as String),
      uploadedAt: DateTime.parse(
        row['uploaded_at'] as String? ?? row['created_at'] as String,
      ),
      imagePath: row['image_path'] as String? ?? '',
      imageUrl: imageUrl,
      imageSha256Hash: row['image_sha256_hash'] as String? ?? '',
      imageQualityPassed:
          ((row['payload'] as Map<String, dynamic>?)?['image_quality_passed']
              as bool?) ??
          false,
      imageLuminance:
          ((row['payload'] as Map<String, dynamic>?)?['image_luminance']
                  as num?)
              ?.toDouble() ??
          0,
      issueCategory: IssueCategory.values.firstWhere(
        (category) => category.name == row['issue_category'],
        orElse: () => IssueCategory.other,
      ),
      aiSuggestedCategory:
          (row['payload'] as Map<String, dynamic>?)?['ai_suggested_category']
              as String?,
      aiConfidence:
          ((row['payload'] as Map<String, dynamic>?)?['ai_confidence'] as num?)
              ?.toDouble(),
      isUrgentFlagged: row['is_urgent_flagged'] as bool? ?? false,
      urgencyConsequence: UrgencyConsequence.values.firstWhere(
        (consequence) => consequence.name == row['urgency_consequence'],
        orElse: () => UrgencyConsequence.standardResidential,
      ),
      description: row['description'] as String? ?? '',
      status: workflowStatus,
      estimatedPriorityScore:
          (row['estimated_priority_score'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_reports.isEmpty && _loadError == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.assignment_late_outlined,
                size: 64,
                color: Colors.blueGrey.shade300,
              ),
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

    if (_reports.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _loadReports,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
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
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              Text(
                'Your Supabase reports (${_reports.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                tooltip: 'Refresh reports',
                onPressed: _loading ? null : _loadReports,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
        ),
        if (_loadError != null)
          MaterialBanner(
            content: Text(_loadError!),
            actions: [
              TextButton(onPressed: _loadReports, child: const Text('Retry')),
            ],
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
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
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
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'URGENT • V=${r.urgencyConsequence.vWeight}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                            child: r.imageUrl != null
                                ? Image.network(
                                    r.imageUrl!,
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            _reportImagePlaceholder(),
                                  )
                                : r.imagePath.isNotEmpty
                                ? Image.file(
                                    File(r.imagePath),
                                    width: 72,
                                    height: 72,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            _reportImagePlaceholder(),
                                  )
                                : _reportImagePlaceholder(),
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
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  'GPS: ${r.latitude.toStringAsFixed(4)}, ${r.longitude.toStringAsFixed(4)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                                Text(
                                  'Triage: ${r.issueCategory.triageQueue} (Score: ${r.estimatedPriorityScore})',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF0D47A1),
                                    fontWeight: FontWeight.w600,
                                  ),
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
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
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
                                    color: isDone
                                        ? Colors.black87
                                        : Colors.grey,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 10),
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

  Widget _reportImagePlaceholder() => Container(
    width: 72,
    height: 72,
    color: Colors.grey.shade300,
    child: const Icon(Icons.image),
  );
}

class DrainRankUtilityPage extends StatefulWidget {
  final String title;

  const DrainRankUtilityPage({super.key, required this.title});

  @override
  State<DrainRankUtilityPage> createState() => _DrainRankUtilityPageState();
}

class _DrainRankUtilityPageState extends State<DrainRankUtilityPage> {
  bool notificationsEnabled = true;
  bool locationEnabled = true;
  bool confirmationEnabled = true;

  @override
  Widget build(BuildContext context) {
    final isSettings = widget.title == 'Settings';

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (isSettings) ...[
            const Text(
              'Preferences',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Manage your app preferences.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.notifications_active_outlined),
                    title: const Text('Notifications'),
                    subtitle: const Text('Notification preference'),
                    value: notificationsEnabled,
                    onChanged: (value) {
                      setState(() => notificationsEnabled = value);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.location_on_outlined),
                    title: const Text('Location services'),
                    subtitle: const Text('Allow location-based reporting'),
                    value: locationEnabled,
                    onChanged: (value) {
                      setState(() => locationEnabled = value);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.check_circle_outline),
                    title: const Text('Submission confirmation'),
                    subtitle: const Text('Show report submission feedback'),
                    value: confirmationEnabled,
                    onChanged: (value) {
                      setState(() => confirmationEnabled = value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'These preferences currently apply only to this screen. '
              'Persisting them and connecting them to app behaviour '
              'will be a separate step.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
          ] else if (widget.title == 'Saved Locations') ...[
            const Icon(
              Icons.location_on_outlined,
              size: 48,
              color: Color(0xFF0F766E),
            ),
            const SizedBox(height: 12),
            const Text(
              'No saved locations yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Saved reporting locations will appear here '
              'when location saving is implemented.',
            ),
          ] else if (widget.title == 'Help & Support') ...[
            const Text(
              'How can we help?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const ListTile(
              leading: Icon(Icons.camera_alt_outlined),
              title: Text('Reporting a blocked drain'),
              subtitle: Text('Capture a clear photo and include the location.'),
            ),
            const ListTile(
              leading: Icon(Icons.track_changes_outlined),
              title: Text('Tracking a report'),
              subtitle: Text(
                'Open Track Status to view available report updates.',
              ),
            ),
          ] else if (widget.title == 'About DrainRank') ...[
            const Icon(
              Icons.water_drop_rounded,
              size: 48,
              color: Color(0xFF0F766E),
            ),
            const SizedBox(height: 12),
            const Text(
              'DrainRank',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Cleaner Drains, Safer Cities',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            const Text(
              'A citizen reporting interface for documenting '
              'drainage issues and tracking their status.',
            ),
          ] else ...[
            const Text('This page is not available yet.'),
          ],
        ],
      ),
    );
  }
}
