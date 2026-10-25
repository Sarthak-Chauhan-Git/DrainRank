import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
const _debugToolPin = '12345678';
const _debugStatusOverridesKey = 'citizen_debug_status_overrides';

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
  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool('citizen_debug_tool_unlocked', false);
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
      title: AppConstants.appName,
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
            () => _error = 'Account created. Check your email to confirm it, then sign in.',
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
                    Image.asset(
                      'assets/logo.png',
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'पहचान से समाधान तक।',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF0F766E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
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
  int _trackRefreshKey = 0;
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
        toolbarHeight: 72,
        titleSpacing: 12,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Image.asset(
                  'assets/logo.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Pravah Samadhan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: -0.4,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'पहचान से समाधान तक।',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFCBD5E1),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
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
                  final preferences = await SharedPreferences.getInstance();
                  await preferences.setBool(
                    'citizen_debug_tool_unlocked',
                    false,
                  );
                  await Supabase.instance.client.auth.signOut();
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not sign out: $error')),
                  );
                }
                return;
              }

              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DrainRankUtilityPage(title: value),
                ),
              );
              if (value == 'Debug Tool' && mounted) {
                setState(() => _trackRefreshKey++);
              }
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
                value: 'Debug Tool',
                child: ListTile(
                  leading: Icon(Icons.build_circle_outlined),
                  title: Text('Debug Tool'),
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
                value: 'About Pravah',
                child: ListTile(
                  leading: Icon(Icons.info_outline_rounded),
                  title: Text('About Pravah'),
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
          : TrackStatusTab(key: ValueKey(_trackRefreshKey)),
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
  int _urgencyLookupGeneration = 0;
  List<NearbyUrgencyFacility> _nearbyFacilities = [];
  String? _urgencyLookupError;

  bool _isLoadingGps = false;
  bool _isSubmitting = false;

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
      final preferences = await SharedPreferences.getInstance();
      final useFixedLocation =
          preferences.getBool('citizen_debug_tool_unlocked') == true &&
          preferences.getBool('citizen_use_fixed_test_location') == true;
      final fixedLatitude = preferences.getDouble(
        'citizen_fixed_test_latitude',
      );
      final fixedLongitude = preferences.getDouble(
        'citizen_fixed_test_longitude',
      );

      if (useFixedLocation && fixedLatitude != null && fixedLongitude != null) {
        lat = fixedLatitude;
        lng = fixedLongitude;
        acc = 5;
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
        _isUrgentFlagged = false;
        _selectedConsequence = UrgencyConsequence.standardResidential;
        _matchedDrain = matched;
        _aiSuggestedLabel = null;
        _aiConfidence = null;
        _selectedCategory = IssueCategory.blockedDrain;

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
    // Use the coordinates associated with the current report.
    final latitude = _latitude;
    final longitude = _longitude;

    if (latitude == null || longitude == null) {
      setState(() => _isUrgentFlagged = false);
      return;
    }

    final lookupGeneration = ++_urgencyLookupGeneration;
    setState(() {
      _isCheckingUrgency = true;
      _isUrgentFlagged = false;
      _nearbyFacilities = [];
      _urgencyLookupError = null;
      _selectedConsequence = UrgencyConsequence.standardResidential;
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

      if (!mounted || lookupGeneration != _urgencyLookupGeneration) return;

      if (nearbyPlaces.isEmpty) {
        setState(() {
          _nearbyFacilities = nearbyPlaces;
          _isUrgentFlagged = false;
          _selectedConsequence = UrgencyConsequence.standardResidential;
        });
        return;
      }

      setState(() {
        _nearbyFacilities = nearbyPlaces;
        _isUrgentFlagged = true;
        _selectedConsequence = UrgencyConsequence.criticalHospitalSchool;
      });
    } catch (e, stackTrace) {
      debugPrint('URGENT FACILITY VERIFICATION ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted || lookupGeneration != _urgencyLookupGeneration) return;

      setState(() {
        _nearbyFacilities = [];
        _urgencyLookupError = e.toString();
        _isUrgentFlagged = false;
        _selectedConsequence = UrgencyConsequence.standardResidential;
      });
    } finally {
      if (mounted && lookupGeneration == _urgencyLookupGeneration) {
        setState(() {
          _isCheckingUrgency = false;
        });
      }
    }
  }

  Widget _buildNearbyFacilitiesMap() {
    final latitude = _latitude;
    final longitude = _longitude;
    if (latitude == null || longitude == null) return const SizedBox.shrink();

    final nearest = _nearbyFacilities.isEmpty ? null : _nearbyFacilities.first;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.map_outlined, color: Color(0xFF0F766E)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Nearby facilities',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                const Text(
                  '500 m zone',
                  style: TextStyle(
                    color: Color(0xFF0F766E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_isCheckingUrgency)
              const Text(
                'Searching hospitals, schools, and emergency services…',
              )
            else if (_urgencyLookupError != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Facility search failed: $_urgencyLookupError',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Retry facility search',
                    onPressed: _verifyHighUrgencyLocation,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              )
            else
              Text(
                nearest == null
                    ? 'No matching facilities found within 500 m.'
                    : '${_nearbyFacilities.length} matching facility/facilities; '
                          '${nearest.name} is nearest '
                          '(${nearest.distanceMeters.toStringAsFixed(0)} m).',
              ),
            const SizedBox(height: 10),
            SizedBox(
              height: 190,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(latitude, longitude),
                    initialZoom: 14.5,
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
                          point: LatLng(latitude, longitude),
                          radius: HighUrgencyPlacesService.defaultRadiusMeters,
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
                          point: LatLng(latitude, longitude),
                          width: 36,
                          height: 36,
                          child: const Icon(
                            Icons.location_on,
                            color: Color(0xFFB91C1C),
                            size: 34,
                          ),
                        ),
                        for (final place in _nearbyFacilities)
                          Marker(
                            point: LatLng(place.latitude, place.longitude),
                            width: 32,
                            height: 32,
                            child: Tooltip(
                              message:
                                  '${place.name} · '
                                  '${place.distanceMeters.toStringAsFixed(0)} m',
                              child: const Icon(
                                Icons.place,
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
              'The circle shows the 500 m search radius. '
              'Facility pins are based on Geoapify Places results.',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
            for (final place in _nearbyFacilities.take(5))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.place_outlined,
                  color: Color(0xFF7C3AED),
                ),
                title: Text(place.name),
                subtitle: Text(place.type),
                trailing: Text('${place.distanceMeters.toStringAsFixed(0)} m'),
              ),
          ],
        ),
      ),
    );
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

  void _showUrgencyInformation() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('How is urgency assessed?'),
        content: const Text(
          'The report location is checked for nearby critical facilities '
          'within 500 metres. Reports near qualifying facilities may be '
          'marked high urgency automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it'),
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

        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isUrgentFlagged ? const Color(0xFFFFE4E6) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isUrgentFlagged
                  ? const Color(0xFFB91C1C)
                  : const Color(0xFFD8E4E8),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _isUrgentFlagged
                      ? const Color(0xFF991B1B)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  _isUrgentFlagged
                      ? Icons.priority_high_rounded
                      : Icons.verified_outlined,
                  color: _isUrgentFlagged
                      ? Colors.white
                      : const Color(0xFF475569),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Column(
                    key: ValueKey(
                      _isCheckingUrgency ? 'checking' : _isUrgentFlagged,
                    ),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isCheckingUrgency
                            ? 'Checking area priority'
                            : _isUrgentFlagged
                            ? 'High urgency detected'
                            : 'Standard priority',
                        style: TextStyle(
                          color: _isUrgentFlagged
                              ? const Color(0xFF7F1D1D)
                              : const Color(0xFF0F172A),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _isCheckingUrgency
                            ? 'Assessing nearby facilities…'
                            : _isUrgentFlagged
                            ? 'This area is near a critical facility.'
                            : 'Urgency is assessed automatically from the area.',
                        style: TextStyle(
                          color: _isUrgentFlagged
                              ? const Color(0xFF991B1B)
                              : const Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'About automatic urgency',
                onPressed: _showUrgencyInformation,
                icon: Icon(
                  Icons.info_outline_rounded,
                  color: _isUrgentFlagged
                      ? const Color(0xFF991B1B)
                      : const Color(0xFF64748B),
                ),
              ),
              if (_isCheckingUrgency)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildNearbyFacilitiesMap(),
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
                    hintText: 'e.g., Drain is completely blocked with plastic garbage near Hospital Gate 2',
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
  Map<String, ReportWorkflowStatus> _debugStatusOverrides = {};
  RealtimeChannel? _reportsChannel;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _reportsChannel = Supabase.instance.client
          .channel('citizen-reports-${user.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'citizen_reports',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'reporter_id',
              value: user.id,
            ),
            callback: (_) => unawaited(_loadReports()),
          )
          .subscribe();
    }
    _loadReports();
  }

  @override
  void dispose() {
    final channel = _reportsChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.dispose();
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
      final preferences = await SharedPreferences.getInstance();
      final rawOverrides = preferences.getString(
        '${_debugStatusOverridesKey}_${user.id}',
      );
      final decodedOverrides = rawOverrides == null
          ? <String, dynamic>{}
          : jsonDecode(rawOverrides) as Map<String, dynamic>;
      final statusOverrides = <String, ReportWorkflowStatus>{};
      for (final entry in decodedOverrides.entries) {
        for (final status in ReportWorkflowStatus.values) {
          if (status.name == entry.value) {
            statusOverrides[entry.key] = status;
            break;
          }
        }
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
          _debugStatusOverrides = statusOverrides;
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
      'cleaning_completed' => ReportWorkflowStatus.cleaningCompleted,
      'under_monitoring' ||
      'monitoring' => ReportWorkflowStatus.underMonitoring,
      'resolved' => ReportWorkflowStatus.resolved,
      'duplicate' => ReportWorkflowStatus.duplicate,
      'withdrawn' => ReportWorkflowStatus.withdrawn,
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

  Future<void> _withdrawReport(CitizenReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Withdraw this report?'),
        content: const Text(
          'You can withdraw a report before work is assigned. '
          'The municipality will no longer process it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep report'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Withdraw report'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client.rpc(
        'withdraw_citizen_report',
        params: {'p_report_id': report.reportId},
      );
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        try {
          await DrainRankEngine.cacheReports(
            _reports
                .map(
                  (cachedReport) => cachedReport.reportId == report.reportId
                      ? cachedReport.copyWith(
                          status: ReportWorkflowStatus.withdrawn,
                        )
                      : cachedReport,
                )
                .toList(),
            userId: userId,
          );
        } catch (cacheError) {
          debugPrint('Could not cache withdrawn report status: $cacheError');
        }
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Report withdrawn.')));
      await _loadReports();
    } catch (error) {
      if (!mounted) return;
      final errorMessage = error.toString();
      final message = errorMessage.contains('42501')
          ? 'Could not withdraw report: Supabase denied access. Apply migration '
                '202610250001_owner_authorized_report_withdrawal.sql. If it is '
                'already applied, confirm this account owns the report and '
                'that work has not been assigned.'
          : 'Could not withdraw report: $errorMessage';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_reports.isEmpty && _loadError == null) {
      return RefreshIndicator(
        onRefresh: _loadReports,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                    'Switch to Report Issue to submit your first report.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFFEAF4F3),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              Text(
                'Your reports (${_reports.length})',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Text(
                'Status updates live • Pull down to refresh',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
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
          child: RefreshIndicator(
            onRefresh: _loadReports,
            child: _reports.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.cloud_off_outlined, size: 48),
                            SizedBox(height: 12),
                            Text(
                              'Pull down to try again.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    itemCount: _reports.length,
                    itemBuilder: (context, index) {
                      final r = _reports[index];
                      final displayedStatus =
                          _debugStatusOverrides[r.reportId] ?? r.status;
                      final canWithdraw =
                          r.status == ReportWorkflowStatus.complaintReceived ||
                          r.status == ReportWorkflowStatus.underVerification;
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
                                        color: const Color(0xFFFFE4E6),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        'HIGH URGENCY',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF991B1B),
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
                                            errorBuilder: (
                                              context,
                                              error,
                                              stackTrace,
                                            ) => _reportImagePlaceholder(),
                                          )
                                        : r.imagePath.isNotEmpty
                                        ? Image.file(
                                            File(r.imagePath),
                                            width: 72,
                                            height: 72,
                                            fit: BoxFit.cover,
                                            errorBuilder: (
                                              context,
                                              error,
                                              stackTrace,
                                            ) => _reportImagePlaceholder(),
                                          )
                                        : _reportImagePlaceholder(),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                              if (_debugStatusOverrides.containsKey(
                                r.reportId,
                              )) ...[
                                const SizedBox(height: 6),
                                const Text(
                                  'Demo status only — not saved to municipal records.',
                                  style: TextStyle(
                                    color: Color(0xFFB45309),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              if ({
                                ReportWorkflowStatus.withdrawn,
                                ReportWorkflowStatus.duplicate,
                                ReportWorkflowStatus.resolved,
                              }.contains(displayedStatus))
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.cancel_outlined,
                                    color: Color(0xFF64748B),
                                  ),
                                  title: Text(displayedStatus.title),
                                  subtitle: Text(displayedStatus.subtitle),
                                )
                              else
                                ...ReportWorkflowStatus.values
                                    .where(
                                      (stage) =>
                                          stage !=
                                              ReportWorkflowStatus.withdrawn &&
                                          stage !=
                                              ReportWorkflowStatus.duplicate &&
                                          stage !=
                                              ReportWorkflowStatus.resolved,
                                    )
                                    .map((stage) {
                                      final isDone =
                                          stage.stepIndex <=
                                          displayedStatus.stepIndex;
                                      final isCurrent =
                                          stage.stepIndex ==
                                          displayedStatus.stepIndex;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 3,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isDone
                                                  ? Icons.check_circle
                                                  : Icons
                                                        .radio_button_unchecked,
                                              size: 18,
                                              color: isCurrent
                                                  ? Colors.orange.shade800
                                                  : (isDone
                                                        ? Colors.green
                                                        : Colors.grey),
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
                              if (canWithdraw)
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _withdrawReport(r),
                                    icon: const Icon(Icons.undo_rounded),
                                    label: const Text('Withdraw report'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
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
  final _fixedLatitudeController = TextEditingController();
  final _fixedLongitudeController = TextEditingController();
  final _debugPinController = TextEditingController();
  bool _fixedLocationEnabled = false;
  bool _fixedLocationLoading = true;
  String? _fixedLocationError;
  bool _debugUnlocked = false;
  String? _debugPinError;
  bool _debugReportsLoading = false;
  bool _debugActionInProgress = false;
  String? _debugReportsError;
  List<Map<String, dynamic>> _debugReports = [];
  String? _selectedDebugReportId;
  ReportWorkflowStatus _simulatedStatus =
      ReportWorkflowStatus.complaintReceived;

  @override
  void initState() {
    super.initState();
    _loadFixedLocation();
  }

  @override
  void dispose() {
    _fixedLatitudeController.dispose();
    _fixedLongitudeController.dispose();
    _debugPinController.dispose();
    super.dispose();
  }

  Future<void> _loadFixedLocation() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _fixedLatitudeController.text =
            preferences.getDouble('citizen_fixed_test_latitude')?.toString() ??
            '';
        _fixedLongitudeController.text =
            preferences.getDouble('citizen_fixed_test_longitude')?.toString() ??
            '';
        _fixedLocationEnabled =
            preferences.getBool('citizen_use_fixed_test_location') ?? false;
        _fixedLocationLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _fixedLocationError = 'Could not load the test location: $error';
        _fixedLocationLoading = false;
      });
    }
  }

  Future<void> _unlockDebugTool() async {
    if (_debugPinController.text != _debugToolPin) {
      setState(() => _debugPinError = 'Incorrect demo PIN.');
      return;
    }
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('citizen_debug_tool_unlocked', true);
      if (!mounted) return;
      setState(() {
        _debugUnlocked = true;
        _debugPinError = null;
      });
      await _loadFixedLocation();
      await _loadDebugReports();
    } catch (error) {
      if (!mounted) return;
      setState(() => _debugPinError = 'Could not unlock debug tools: $error');
    }
  }

  Future<void> _loadDebugReports() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      setState(() {
        _debugReports = [];
        _debugReportsError = 'Sign in to manage this account’s test reports.';
        _debugReportsLoading = false;
      });
      return;
    }
    setState(() {
      _debugReportsLoading = true;
      _debugReportsError = null;
    });
    try {
      final rows = await client
          .from('citizen_reports')
          .select('report_id,status,issue_category')
          .eq('reporter_id', user.id)
          .order('created_at', ascending: false);
      if (!mounted) return;
      final reports = rows
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      setState(() {
        _debugReports = reports;
        _debugReportsLoading = false;
        if (!_debugReports.any(
          (row) => row['report_id'] == _selectedDebugReportId,
        )) {
          _selectedDebugReportId = reports.isEmpty
              ? null
              : reports.first['report_id'] as String;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _debugReportsError = 'Could not load your reports: $error';
        _debugReportsLoading = false;
      });
    }
  }

  Future<void> _saveSimulatedStatus() async {
    final reportId = _selectedDebugReportId;
    final user = Supabase.instance.client.auth.currentUser;
    if (reportId == null || user == null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = '${_debugStatusOverridesKey}_${user.id}';
      final overrides = <String, dynamic>{
        ...?jsonDecode(preferences.getString(key) ?? '{}')
            as Map<String, dynamic>?,
        reportId: _simulatedStatus.name,
      };
      await preferences.setString(key, jsonEncode(overrides));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo status saved on this phone only.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save demo status: $error')),
      );
    }
  }

  Future<void> _clearSimulatedStatuses() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove('${_debugStatusOverridesKey}_${user.id}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo status overrides cleared.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear demo statuses: $error')),
      );
    }
  }

  Future<void> _deleteDebugReports({List<String>? reportIds}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          reportIds == null
              ? 'Reset this account’s test data?'
              : 'Delete report?',
        ),
        content: Text(
          reportIds == null
              ? 'This removes your own reports only when work has not been assigned. Your account and assigned reports will be kept.'
              : 'This removes this report only if it belongs to your account and has not been assigned.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              reportIds == null ? 'Reset test data' : 'Delete report',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _debugActionInProgress = true);
    try {
      final client = Supabase.instance.client;
      final response = await client.rpc(
        'debug_delete_citizen_reports',
        params: {'p_report_ids': reportIds},
      );
      final result = Map<String, dynamic>.from(response as Map);
      final deletedIds = List<String>.from(
        result['deleted_report_ids'] as List? ?? const [],
      );
      final imagePaths = List<String>.from(
        result['image_paths'] as List? ?? const [],
      );
      var storageError = '';
      if (imagePaths.isNotEmpty) {
        try {
          await client.storage.from('citizen-photos').remove(imagePaths);
        } catch (error) {
          storageError = ' Report images could not all be removed: $error';
        }
      }
      final user = client.auth.currentUser;
      if (user != null) {
        final preferences = await SharedPreferences.getInstance();
        final cached = await DrainRankEngine.getSavedReports(userId: user.id);
        await DrainRankEngine.cacheReports(
          cached
              .where((report) => !deletedIds.contains(report.reportId))
              .toList(),
          userId: user.id,
        );
        final statusKey = '${_debugStatusOverridesKey}_${user.id}';
        final statusOverrides = <String, dynamic>{
          ...?jsonDecode(preferences.getString(statusKey) ?? '{}')
              as Map<String, dynamic>?,
        }..removeWhere((id, _) => deletedIds.contains(id));
        await preferences.setString(statusKey, jsonEncode(statusOverrides));
      }
      await _loadDebugReports();
      if (!mounted) return;
      final skipped = result['skipped_assigned_count'] as int? ?? 0;
      final message = reportIds == null
          ? 'Removed ${deletedIds.length} unassigned report(s).'
          : deletedIds.isEmpty
          ? 'No report was deleted; it may already be assigned.'
          : 'Report deleted.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$message${skipped > 0 ? ' $skipped assigned report(s) were kept.' : ''}$storageError',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reset test data: $error')),
      );
    } finally {
      if (mounted) setState(() => _debugActionInProgress = false);
    }
  }

  Future<void> _resetDebugLocation() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove('citizen_fixed_test_latitude');
      await preferences.remove('citizen_fixed_test_longitude');
      await preferences.setBool('citizen_use_fixed_test_location', false);
      if (!mounted) return;
      setState(() {
        _fixedLatitudeController.clear();
        _fixedLongitudeController.clear();
        _fixedLocationEnabled = false;
        _fixedLocationError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _fixedLocationError = 'Could not reset test location: $error',
      );
    }
  }

  Widget _buildDebugTool() {
    if (!_debugUnlocked) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 42,
                color: Color(0xFF0F766E),
              ),
              const SizedBox(height: 10),
              const Text(
                'Demo and testing tools',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the demo PIN to continue. Debug controls can change this account’s test reports and location.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _debugPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                decoration: const InputDecoration(
                  labelText: 'Demo PIN',
                  prefixIcon: Icon(Icons.password_rounded),
                  counterText: '',
                ),
                onSubmitted: (_) => _unlockDebugTool(),
              ),
              if (_debugPinError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _debugPinError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _unlockDebugTool,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('Unlock debug tools'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Temporary demo PINs are visible in the app binary. This gate is not a security boundary; do not use it to protect production data.',
                style: TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fixed report location',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'While enabled, new reports use these coordinates instead of device GPS.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _fixedLatitudeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    prefixIcon: Icon(Icons.north),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _fixedLongitudeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    prefixIcon: Icon(Icons.east),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use fixed location'),
                  subtitle: const Text('Affects new reports on this account.'),
                  value: _fixedLocationEnabled,
                  onChanged: (value) => _saveFixedLocation(enabled: value),
                ),
                if (_fixedLocationError != null)
                  Text(
                    _fixedLocationError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _fixedLocationLoading
                          ? null
                          : () => _saveFixedLocation(),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save location'),
                    ),
                    OutlinedButton(
                      onPressed: _resetDebugLocation,
                      child: const Text('Clear location'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Simulate report status',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'This preview is stored on this phone only and does not change municipal records.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                if (_debugReportsLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_debugReportsError != null)
                  Text(
                    _debugReportsError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                else if (_debugReports.isEmpty)
                  const Text('No reports are available for this account.')
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: _selectedDebugReportId,
                    decoration: const InputDecoration(labelText: 'Report'),
                    items: _debugReports.map((row) {
                      final id = row['report_id'] as String;
                      final issue = row['issue_category']?.toString() ?? '';
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                          '$id${issue.isEmpty ? '' : ' • $issue'}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setState(() => _selectedDebugReportId = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<ReportWorkflowStatus>(
                    initialValue: _simulatedStatus,
                    decoration: const InputDecoration(
                      labelText: 'Preview status',
                    ),
                    items: ReportWorkflowStatus.values
                        .where(
                          (status) => status != ReportWorkflowStatus.withdrawn,
                        )
                        .map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(status.title),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _simulatedStatus = value);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _saveSimulatedStatus,
                        child: const Text('Apply demo status'),
                      ),
                      OutlinedButton(
                        onPressed: _clearSimulatedStatuses,
                        child: const Text('Clear all demo statuses'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Your test reports',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Only reports owned by this signed-in account can be removed. Assigned reports are always kept.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                if (_debugReportsError != null)
                  Text(
                    _debugReportsError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                else
                  for (final row in _debugReports)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(row['report_id'] as String),
                      subtitle: Text(
                        '${row['issue_category'] ?? 'Report'} • ${row['status'] ?? 'Unknown status'}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Delete unassigned report',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFB91C1C),
                        ),
                        onPressed: _debugActionInProgress
                            ? null
                            : () => _deleteDebugReports(
                                reportIds: [row['report_id'] as String],
                              ),
                      ),
                    ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFB91C1C),
                  ),
                  onPressed: _debugActionInProgress
                      ? null
                      : () => _deleteDebugReports(),
                  icon: _debugActionInProgress
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Reset my unassigned test reports'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveFixedLocation({bool? enabled}) async {
    if (enabled == false) {
      try {
        final preferences = await SharedPreferences.getInstance();
        await preferences.setBool('citizen_use_fixed_test_location', false);
        if (!mounted) return;
        setState(() {
          _fixedLocationEnabled = false;
          _fixedLocationError = null;
        });
      } catch (error) {
        if (!mounted) return;
        setState(
          () => _fixedLocationError = 'Could not disable test location: $error',
        );
      }
      return;
    }

    final latitude = double.tryParse(_fixedLatitudeController.text.trim());
    final longitude = double.tryParse(_fixedLongitudeController.text.trim());
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      setState(
        () => _fixedLocationError =
            'Enter a valid latitude (-90 to 90) and longitude (-180 to 180).',
      );
      return;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      final shouldEnable = enabled ?? _fixedLocationEnabled;
      final latitudeSaved = await preferences.setDouble(
        'citizen_fixed_test_latitude',
        latitude,
      );
      final longitudeSaved = await preferences.setDouble(
        'citizen_fixed_test_longitude',
        longitude,
      );
      final enabledSaved = await preferences.setBool(
        'citizen_use_fixed_test_location',
        shouldEnable,
      );
      if (!latitudeSaved || !longitudeSaved || !enabledSaved) {
        throw StateError('The test location could not be persisted.');
      }
      if (!mounted) return;
      setState(() {
        _fixedLocationEnabled = shouldEnable;
        _fixedLocationError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shouldEnable
                ? 'Test location saved and enabled.'
                : 'Test location saved.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _fixedLocationError = 'Could not save test location: $error',
      );
    }
  }

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
          ] else if (widget.title == 'Debug Tool') ...[
            if (_debugUnlocked && _fixedLocationLoading)
              const Center(child: CircularProgressIndicator())
            else
              _buildDebugTool(),
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
          ] else if (widget.title == 'About Pravah') ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/logo.png',
                width: 64,
                height: 64,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              AppConstants.appName,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'पहचान से समाधान तक।',
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
