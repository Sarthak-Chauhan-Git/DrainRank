
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:typed_data';
import 'dart:math' as math;

import 'firebase_options.dart';


/// Writes real EXIF GPS metadata into the JPEG bytes, not just Firebase fields.
/// Supports Flutter Android and Chrome without platform-specific EXIF plugins.
Uint8List embedGpsExifInJpeg(
    Uint8List jpeg,
    Position position,
    DateTime capturedAt,
    ) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) {
    throw const FormatException(
      'Camera did not produce a JPEG image; cannot embed EXIF GPS tags.',
    );
  }

  Uint8List ascii(String value) =>
      Uint8List.fromList([...value.codeUnits, 0]);

  Uint8List uint32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  Uint8List rational(int numerator, int denominator) {
    final data = ByteData(8)
      ..setUint32(0, numerator, Endian.little)
      ..setUint32(4, denominator, Endian.little);
    return data.buffer.asUint8List();
  }

  Uint8List rationals(List<Uint8List> values) {
    final out = BytesBuilder(copy: false);
    for (final value in values) {
      out.add(value);
    }
    return out.takeBytes();
  }

// EXIF GPS values must be unsigned rational numbers with separate N/S E/W refs.
  Uint8List degreesMinutesSeconds(double coordinate) {
    final value = coordinate.abs();
    final degrees = value.floor();
    final minutesValue = (value - degrees) * 60;
    final minutes = minutesValue.floor();
    final seconds = ((minutesValue - minutes) * 60 * 1000000).round();
    return rationals([
      rational(degrees, 1),
      rational(minutes, 1),
      rational(seconds, 1000000),
    ]);
  }

  String two(int value) => value.toString().padLeft(2, '0');
  final utc = capturedAt.toUtc();
  final localTimestamp =
      '${capturedAt.year.toString().padLeft(4, '0')}:'
      '${two(capturedAt.month)}:${two(capturedAt.day)} '
      '${two(capturedAt.hour)}:${two(capturedAt.minute)}:${two(capturedAt.second)}';
  final gpsDate =
      '${utc.year.toString().padLeft(4, '0')}:'
      '${two(utc.month)}:${two(utc.day)}';

// Each entry: TIFF tag, TIFF type, number of values, encoded value(s).
// Type 1 = byte, 2 = ASCII, 5 = unsigned rational, 4 = uint32.
  final ifd0 = <_GpsExifEntry>[
    _GpsExifEntry(0x0132, 2, 20, ascii(localTimestamp)), // DateTime
    _GpsExifEntry(0x8769, 4, 1, uint32(0)), // Exif IFD offset
    _GpsExifEntry(0x8825, 4, 1, uint32(0)), // GPS IFD offset
  ];
  final exifIfd = <_GpsExifEntry>[
    _GpsExifEntry(0x9003, 2, 20, ascii(localTimestamp)), // DateTimeOriginal
    _GpsExifEntry(0x9004, 2, 20, ascii(localTimestamp)), // DateTimeDigitized
  ];
  final gpsIfd = <_GpsExifEntry>[
    _GpsExifEntry(0x0000, 1, 4, Uint8List.fromList([2, 3, 0, 0])),
    _GpsExifEntry(0x0001, 2, 2,
        Uint8List.fromList([position.latitude < 0 ? 83 : 78, 0])),
    _GpsExifEntry(0x0002, 5, 3, degreesMinutesSeconds(position.latitude)),
    _GpsExifEntry(0x0003, 2, 2,
        Uint8List.fromList([position.longitude < 0 ? 87 : 69, 0])),
    _GpsExifEntry(0x0004, 5, 3, degreesMinutesSeconds(position.longitude)),
    _GpsExifEntry(0x0005, 1, 1,
        Uint8List.fromList([position.altitude < 0 ? 1 : 0])),
    _GpsExifEntry(0x0006, 5, 1,
        rational((position.altitude.abs() * 100).round(), 100)),
    _GpsExifEntry(0x0007, 5, 3, rationals([
      rational(utc.hour, 1),
      rational(utc.minute, 1),
      rational(utc.second * 1000 + utc.millisecond, 1000),
    ])),
    _GpsExifEntry(0x001D, 2, 11, ascii(gpsDate)),
// GPSHPositioningError: estimated horizontal error in meters (EXIF GPS tag 31).
    if (position.accuracy.isFinite && position.accuracy >= 0)
      _GpsExifEntry(0x001F, 5, 1,
          rational((math.min(position.accuracy, 42949672) * 100).round(), 100)),
  ];

  int dirSize(List<_GpsExifEntry> entries) => 2 + entries.length * 12 + 4;
  const ifd0Offset = 8;
  final exifOffset = ifd0Offset + dirSize(ifd0);
  final gpsOffset = exifOffset + dirSize(exifIfd);
  ifd0[1] = _GpsExifEntry(0x8769, 4, 1, uint32(exifOffset));
  ifd0[2] = _GpsExifEntry(0x8825, 4, 1, uint32(gpsOffset));

  var payloadOffset = gpsOffset + dirSize(gpsIfd);
  final chunks = <_GpsExifEntry>[...ifd0, ...exifIfd, ...gpsIfd];
  final outOfLineOffsets = <_GpsExifEntry, int>{};
  for (final entry in chunks) {
    if (entry.value.length > 4) {
      if (payloadOffset.isOdd) payloadOffset++;
      outOfLineOffsets[entry] = payloadOffset;
      payloadOffset += entry.value.length;
    }
  }
  final tiff = Uint8List(payloadOffset);
  final data = ByteData.sublistView(tiff);
  tiff[0] = 0x49; // Little-endian TIFF header: II
  tiff[1] = 0x49;
  data.setUint16(2, 42, Endian.little);
  data.setUint32(4, ifd0Offset, Endian.little);

  void writeIfd(int offset, List<_GpsExifEntry> entries) {
    data.setUint16(offset, entries.length, Endian.little);
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final at = offset + 2 + 12 * i;
      data.setUint16(at, entry.tag, Endian.little);
      data.setUint16(at + 2, entry.type, Endian.little);
      data.setUint32(at + 4, entry.count, Endian.little);
      if (entry.value.length <= 4) {
        tiff.setRange(at + 8, at + 8 + entry.value.length, entry.value);
      } else {
        final payloadAt = outOfLineOffsets[entry]!;
        data.setUint32(at + 8, payloadAt, Endian.little);
        tiff.setRange(payloadAt, payloadAt + entry.value.length, entry.value);
      }
    }
    data.setUint32(offset + 2 + entries.length * 12, 0, Endian.little);
  }

  writeIfd(ifd0Offset, ifd0);
  writeIfd(exifOffset, exifIfd);
  writeIfd(gpsOffset, gpsIfd);

  final app1Payload = BytesBuilder(copy: false)
    ..add([0x45, 0x78, 0x69, 0x66, 0, 0]) // Exif\0\0
    ..add(tiff);
  final segment = app1Payload.takeBytes();
  final segmentLength = segment.length + 2; // Includes length field itself.
  if (segmentLength > 65535) {
    throw const FormatException('EXIF metadata is too large for JPEG APP1.');
  }
// Insert EXIF immediately after JPEG SOI, preserving the original image bytes.
// The resulting bytes (including EXIF) are the bytes uploaded to Firebase.
  final output = BytesBuilder(copy: false)
    ..add(jpeg.sublist(0, 2))
    ..add([0xFF, 0xE1, segmentLength >> 8, segmentLength & 0xFF])
    ..add(segment)
    ..add(jpeg.sublist(2));
  return output.takeBytes();
}

class _GpsExifEntry {
  const _GpsExifEntry(this.tag, this.type, this.count, this.value);
  final int tag;
  final int type;
  final int count;
  final Uint8List value;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MunicipalCrewApp());
}

class MunicipalCrewApp extends StatelessWidget {
  const MunicipalCrewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DRAINRANK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0F766E),
          onPrimary: Color(0xFFFFFFFF),
          primaryContainer: Color(0xFFF0FDFA),
          onPrimaryContainer: Color(0xFF0F172A),
          secondary: Color(0xFF124170),
          onSecondary: Color(0xFFFFFFFF),
          secondaryContainer: Color(0xFFDCEBFA),
          onSecondaryContainer: Color(0xFF1E3A5F),
          tertiary: Color(0xFF67C090),
          onTertiary: Color(0xFF0F172A),
          tertiaryContainer: Color(0xFFEAF8EF),
          onTertiaryContainer: Color(0xFF047857),
          error: Color(0xFFB91C1C),
          onError: Color(0xFFFFFFFF),
          errorContainer: Color(0xFFFEE2E2),
          onErrorContainer: Color(0xFF9F1239),
          surface: Color(0xFFFFFFFF),
          onSurface: Color(0xFF0F172A),
          onSurfaceVariant: Color(0xFF475569),
          outline: Color(0xFFB9DED3),
          outlineVariant: Color(0xFFD7E5E7),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFFFF),
          foregroundColor: Color(0xFF0F172A),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF124170),
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: IconThemeData(color: Color(0xFF0F766E)),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFFFFFF),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFD7E5E7)),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFFF0FDFA),
          indicatorColor: Color(0xFFE8F8F1),
          iconTheme: WidgetStatePropertyAll(
            IconThemeData(color: Color(0xFF0F766E)),
          ),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.w600),
          ),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFFF3FAF6),
          surfaceTintColor: Colors.transparent,
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF0F766E),
          textColor: Color(0xFF334155),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
            foregroundColor: const Color(0xFFFFFFFF),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0F766E),
            side: const BorderSide(color: Color(0xFFB9DED3)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD7E5E7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD7E5E7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF14B8A6), width: 1.6),
          ),
          labelStyle: const TextStyle(color: Color(0xFF1E3A5F)),
          hintStyle: const TextStyle(color: Color(0xFF64748B)),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFFF0FDFA),
          selectedColor: const Color(0xFFE8F8F1),
          side: const BorderSide(color: Color(0xFFB9DED3)),
          labelStyle: const TextStyle(color: Color(0xFF1E3A5F)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        dividerColor: const Color(0xFFE7EEF0),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(color: Color(0xFF124170), fontWeight: FontWeight.w700),
          titleLarge: TextStyle(color: Color(0xFF124170), fontWeight: FontWeight.w700),
          titleMedium: TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: Color(0xFF334155)),
          bodyMedium: TextStyle(color: Color(0xFF334155)),
          bodySmall: TextStyle(color: Color(0xFF64748B)),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        if (snapshot.data == null) return const CrewLoginPage();
        return RoleCheckPage(user: snapshot.data!);
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

void showAppMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ));
}

/// Admin-created Firebase Auth accounts must use this same internal email
/// alias for each Municipal ID. Crew members only enter their Municipal ID.
String internalEmailForMunicipalId(String municipalId) {
  final normalizedId = municipalId.trim().toLowerCase();
  return '$normalizedId@crew.municipal.local';
}

class RoleCheckPage extends StatelessWidget {
  const RoleCheckPage({super.key, required this.user});
  final User user;

  Future<bool> _isAdmin() async {
    final token = await user.getIdTokenResult(true);
    return token.claims?['admin'] == true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        if (snapshot.hasError) {
          return _AccessMessageScreen(
            title: 'Unable to verify account',
            message: 'Please log out and try again. If the problem continues, contact the Municipal Board.',
            onPressed: () => FirebaseAuth.instance.signOut(),
          );
        }
        if (snapshot.data == true) {
          return AdminDashboardPage(user: user);
        }
        return AccessCheckPage(user: user);
      },
    );
  }
}

class CrewLoginPage extends StatefulWidget {
  const CrewLoginPage({super.key});

  @override
  State<CrewLoginPage> createState() => _CrewLoginPageState();
}

class _CrewLoginPageState extends State<CrewLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _municipalIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _adminLogin = false;
  bool _loading = false;
  bool _hidePassword = true;
  final FocusNode _passwordFocus = FocusNode();

  @override
  void dispose() {
    _municipalIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final email = _adminLogin
          ? _emailController.text.trim()
          : internalEmailForMunicipalId(_municipalIdController.text);
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text,
      );
      if (_adminLogin) {
        final token = await credential.user!.getIdTokenResult(true);
        if (token.claims?['admin'] != true) {
          await FirebaseAuth.instance.signOut();
          if (mounted) showAppMessage(context, 'This account is not authorized as an administrator.');
        }
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if ([
        'invalid-credential',
        'user-not-found',
        'wrong-password',
        'invalid-email',
      ].contains(e.code)) {
        showAppMessage(context, _adminLogin
            ? 'Wrong admin email or password.'
            : 'Wrong Municipal ID or password.');
      } else if (e.code == 'too-many-requests') {
        showAppMessage(
          context,
          'Too many login attempts. Please wait and try again.',
        );
      } else if (e.code == 'network-request-failed') {
        showAppMessage(
          context,
          'Network error. Check your internet connection and try again.',
        );
      } else {
        showAppMessage(
          context,
          'Unable to log in right now. Please try again later.',
        );
        debugPrint('Login error [${e.code}]: ${e.message}');
      }
    } catch (e) {
      if (!mounted) return;
      showAppMessage(context, 'Unable to log in. Please try again.');
      debugPrint('Unexpected login error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.location_city_rounded,
                        size: 82, color: const Color(0xFF0F766E)),
                    const SizedBox(height: 22),
                    Text(
                      _adminLogin ? 'Municipal Board Admin Login' : 'Municipal Crew Login',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _adminLogin
                          ? 'Sign in with your authorized administrator email and password.'
                          : 'Sign in using the credentials provided by your Municipal Board.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_adminLogin)
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                        decoration: const InputDecoration(
                          labelText: 'Admin email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                        validator: (value) => _adminLogin &&
                            (value == null || !value.contains('@'))
                            ? 'Enter a valid admin email'
                            : null,
                      )
                    else
                      TextFormField(
                        controller: _municipalIdController,
                        textInputAction: TextInputAction.next,
                        onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Municipal ID',
                          hintText: 'Enter your unique Municipal ID',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (value) =>
                        value == null || value.trim().isEmpty
                            ? 'Enter your Municipal ID'
                            : null,
                      ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      textInputAction: TextInputAction.go,
                      obscureText: _hidePassword,
                      onFieldSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _hidePassword ? 'Show password' : 'Hide password',
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                          icon: Icon(_hidePassword
                              ? Icons.visibility_off
                              : Icons.visibility),
                        ),
                      ),
                      validator: (value) =>
                      value == null || value.isEmpty
                          ? 'Enter your password'
                          : null,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _loading ? null : _login,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: _loading
                            ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : const Text('LOG IN',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                        _adminLogin = !_adminLogin;
                        _formKey.currentState?.reset();
                        _emailController.clear();
                        _municipalIdController.clear();
                        _passwordController.clear();
                      }),
                      child: Text(_adminLogin
                          ? 'Switch to Crew Login'
                          : 'Municipal Board Admin Login'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _adminLogin
                          ? 'Only accounts authorized by the Municipal Board can access admin features.'
                          : 'Accounts are created by the Municipal Board. Contact the board for account access or password reset.',
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
    );
  }
}

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key, required this.user});
  final User user;

  Future<void> _logout() => FirebaseAuth.instance.signOut();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Municipal Board Admin'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined,
                        size: 72, color: const Color(0xFF0F766E)),
                    const SizedBox(height: 16),
                    const Text('Administrator Dashboard',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'You are signed in with an administrator account.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) =>
                              AdminCreditReviewPage(adminUid: user.uid))),
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Review Work & Award Credits'),
                    ),
                    const SizedBox(height: 16),
                    const ListTile(
                      leading: Icon(Icons.person_add_alt_1),
                      title: Text('Add crew member'),
                      subtitle: Text(
                        'Account creation needs a trusted backend. It is not enabled yet, so this screen cannot create accounts securely.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Next step: connect a secure free-tier backend before enabling account creation. Do not place service-account credentials or admin secrets in this Flutter app.',
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('LOG OUT'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Admin-only review UI. Server rules, not the widget, authorize awards.
class AdminCreditReviewPage extends StatelessWidget {
  const AdminCreditReviewPage({super.key, required this.adminUid});
  final String adminUid;

  Future<void> _approve(BuildContext context, String taskId,
      String uid, String taskTitle) async {
    final input = TextEditingController(text: '10');
    final amount = await showDialog<int>(context: context, builder: (dialogContext) =>
        AlertDialog(title: const Text('Approve work & grant credits'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(taskTitle), const SizedBox(height: 12),
            TextField(controller: input, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Credits to grant (1–1000)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () {
              final points = int.tryParse(input.text.trim());
              if (points == null || points < 1 || points > 1000) return;
              Navigator.pop(dialogContext, points);
            }, child: const Text('Approve')),
          ],
        ));
    input.dispose();
    if (amount == null || !context.mounted) return;
    try {
      final db = FirebaseFirestore.instance;
      final taskRef = db.collection('tasks').doc(taskId);
      final awardRef = db.collection('users').doc(uid).collection('creditAwards').doc(taskId);
      await db.runTransaction((tx) async {
        final task = await tx.get(taskRef);
        final prior = await tx.get(awardRef);
        if (prior.exists) throw StateError('Credits already granted for this task and member.');
        final assigned = task.data()?['assignedToUid'];
        if (!task.exists || assigned is! List || !assigned.contains(uid)) {
          throw StateError('This crew member is not assigned to the task.');
        }
        // The review screen also checks submission evidence before enabling approval.
        tx.set(awardRef, {
          'taskId': taskId,
          'taskTitle': taskTitle,
          'crewUid': uid,
          'credits': amount,
          'approvedByUid': adminUid,
          'approvedAt': FieldValue.serverTimestamp(),
        });
      });
      if (context.mounted) showAppMessage(context, '$amount credits awarded.');
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Could not approve: $e');
    }
  }

  Future<void> _applyOverdueDeductions(BuildContext context) async {
    try {
      final count = await processOverdueDeductionsForAdmin(adminUid);
      if (context.mounted) {
        showAppMessage(context, count == 0
            ? 'No new overdue deductions were needed.'
            : 'Applied $count overdue daily deduction(s).');
      }
    } catch (e) {
      if (context.mounted) showAppMessage(context, 'Could not process overdue deductions: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Review Work & Credits'),
      actions: [
        IconButton(
          tooltip: 'Process overdue deductions',
          onPressed: () => _applyOverdueDeductions(context),
          icon: const Icon(Icons.trending_down),
        ),
      ],
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('tasks').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final task = snapshot.data!.docs[index];
            return Card(child: ExpansionTile(
              title: Text((task.data()['title'] ?? 'Task').toString()),
              subtitle: Text((task.data()['dateKey'] ?? '').toString()),
              children: [
                _DailyOverdueRateEditor(
                  taskReference: task.reference,
                  initialRate: task.data()['dailyOverdueDeduction'] is int
                      ? task.data()['dailyOverdueDeduction'] as int
                      : 0,
                ),
                for (final uid in (task.data()['assignedToUid'] is List
                    ? (task.data()['assignedToUid'] as List).whereType<String>()
                    : <String>[]))
                  FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    future: task.reference.collection('workUpdates')
                        .where('submittedByUid', isEqualTo: uid).get(),
                    builder: (context, proof) {
                      if (!proof.hasData) return const ListTile(title: Text('Checking evidence...'));
                      final hasEvidence = proof.data!.docs.isNotEmpty;
                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance.collection('users').doc(uid)
                            .collection('creditAwards').doc(task.id).snapshots(),
                        builder: (context, award) {
                          final granted = award.data?.exists ?? false;
                          final member = (task.data()['crewMembers'] is List
                              ? (task.data()['crewMembers'] as List).whereType<Map>().toList()
                              : <Map>[]);
                          final matches = member.where((m) => m['uid'] == uid);
                          final name = matches.isEmpty ? uid :
                          (matches.first['name'] ?? matches.first['fullName'] ?? uid).toString();
                          return ListTile(
                            title: Text(name),
                            subtitle: Text(granted ? 'Credits approved' :
                            hasEvidence ? '${proof.data!.docs.length} work photo(s) submitted' :
                            'No work submitted'),
                            trailing: granted ? const Icon(Icons.check_circle, color: const Color(0xFF059669)) :
                            TextButton(onPressed: hasEvidence ?
                                () => _approve(context, task.id, uid,
                                (task.data()['title'] ?? 'Task').toString()) : null,
                                child: const Text('Award credits')),
                          );
                        },
                      );
                    },
                  ),
              ],
            ));
          },
        );
      },
    ),
  );
}

class _DailyOverdueRateEditor extends StatefulWidget {
  const _DailyOverdueRateEditor({
    required this.taskReference,
    required this.initialRate,
  });

  final DocumentReference<Map<String, dynamic>> taskReference;
  final int initialRate;

  @override
  State<_DailyOverdueRateEditor> createState() => _DailyOverdueRateEditorState();
}

class _DailyOverdueRateEditorState extends State<_DailyOverdueRateEditor> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialRate.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveRate() async {
    final rate = int.tryParse(_controller.text.trim());
    if (rate == null || rate < 0 || rate > 1000) {
      showAppMessage(context, 'Enter a daily deduction from 0 to 1000 credits.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.taskReference.update({'dailyOverdueDeduction': rate});
      if (mounted) showAppMessage(context, rate == 0
          ? 'Daily overdue deduction disabled for this task.'
          : 'Daily overdue deduction set to $rate credits.');
    } catch (e) {
      if (mounted) showAppMessage(context, 'Could not save daily deduction: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Daily overdue deduction', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('Set 0 to disable. The admin action applies each missing overdue day once.'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Credits deducted per overdue day',
              prefixIcon: Icon(Icons.trending_down),
            ),
          )),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _saving ? null : _saveRate,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save rate'),
          ),
        ]),
      ],
    ),
  );
}

class AccessCheckPage extends StatefulWidget {
  const AccessCheckPage({super.key, required this.user});
  final User user;

  @override
  State<AccessCheckPage> createState() => _AccessCheckPageState();
}

class _AccessCheckPageState extends State<AccessCheckPage> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .get();
  }

  Future<void> _signOut() => FirebaseAuth.instance.signOut();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return _AccessMessageScreen(
            title: 'Account unavailable',
            message: 'Your crew profile could not be found. Contact the Municipal Board.',
            onPressed: _signOut,
          );
        }

        final profile = snapshot.data!.data()!;
        if (profile['accessBlocked'] == true) {
          return _AccessMessageScreen(
            title: 'Access blocked',
            message: 'Contact Municipal Board.',
            onPressed: _signOut,
          );
        }

        return CrewHomePage(
          user: widget.user,
          profile: profile,
          onLogout: _signOut,
        );
      },
    );
  }
}

class _AccessMessageScreen extends StatelessWidget {
  const _AccessMessageScreen({
    required this.title,
    required this.message,
    required this.onPressed,
  });

  final String title;
  final String message;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.gpp_bad_outlined,
                      size: 76, color: const Color(0xFF0F766E)),
                  const SizedBox(height: 20),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onPressed, child: const Text('LOG OUT')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _dateKey(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _prettyDate(DateTime date) {
  const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
}

/// Immutable, admin-approved credit awards. One award per crew member/task.
/// Uses the user's own Firestore subcollection, so crew cannot read others' totals.
class CrewCredits extends StatelessWidget {
  const CrewCredits({super.key, required this.uid, this.compact = false});
  final String uid;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid)
          .collection('creditAwards').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Current Credits: unavailable');
        }
        final total = snapshot.data?.docs.fold<int>(0, (sum, doc) {
          final amount = doc.data()['credits'];
          return sum + (amount is int ? amount : 0);
        });
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.workspace_premium_outlined, color: const Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          Text('Current Credits: ${total ?? '...'}',
              style: compact ? Theme.of(context).textTheme.titleMedium :
              Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ]);
      },
    );
  }
}

class CrewHomePage extends StatefulWidget {
  const CrewHomePage({
    super.key,
    required this.user,
    required this.profile,
    required this.onLogout,
  });

  final User user;
  final Map<String, dynamic> profile;
  final Future<void> Function() onLogout;

  @override
  State<CrewHomePage> createState() => _CrewHomePageState();
}

class _CrewHomePageState extends State<CrewHomePage> {
// 0 = previous seven days; 1 = today; 2 = upcoming seven days.
  int _selectedTab = 1;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _tasksStream;

  @override
  void initState() {
    super.initState();
    _openTaskStream();
  }

  void _openTaskStream() {
    // Keep this query aligned with the /tasks Firestore security rule.
    // A permission-denied response must be fixed in Firestore Rules.
    final uid = FirebaseAuth.instance.currentUser?.uid ?? widget.user.uid;
    debugPrint('DRAINRANK task query: project=${Firebase.app().options.projectId}, uid=$uid');
    _tasksStream = FirebaseFirestore.instance
        .collection('tasks')
        .where('assignedToUid', arrayContains: uid)
        .snapshots();
  }

  DateTime _dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  String get _crewName {
    final name = (widget.profile['fullName'] ??
        widget.profile['name'] ??
        widget.user.displayName ??
        '')
        .toString()
        .trim();
    return name.isNotEmpty
        ? name
        : (widget.user.email?.split('@').first ?? 'Crew Member');
  }

  List<DateTime> _visibleDays() {
    final today = _dayOnly(DateTime.now());
    if (_selectedTab == 1) return [today];
    if (_selectedTab == 0) {
      return List.generate(7, (i) => today.subtract(Duration(days: 7 - i)));
    }
    return List.generate(7, (i) => today.add(Duration(days: i + 1)));
  }

// Handles both '08:00 AM' and '13:00' time strings for chronological sorting.
  int _timeInMinutes(String? raw) {
    if (raw == null) return 9999;
    final match = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$', caseSensitive: false)
        .firstMatch(raw.trim());
    if (match == null) return 9999;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)?.toUpperCase();
    if (minute > 59 || hour > (period == null ? 23 : 12) || hour == 0 && period != null) {
      return 9999;
    }
    if (period != null) hour = (hour % 12) + (period == 'PM' ? 12 : 0);
    return hour * 60 + minute;
  }

  void _refreshTasks() {
    setState(_openTaskStream);
    showAppMessage(context, 'Refreshing assigned tasks...');
  }

  void _showDetails(String title, Widget content) {
    Navigator.of(context).pop(); // Close drawer before opening detail sheet.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(sheetContext).textTheme.headlineSmall),
              const SizedBox(height: 16),
              content,
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileDetails() {
    final municipalId = (widget.profile['municipalId'] ?? '').toString().trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline),
          title: const Text('Name'),
          subtitle: Text(_crewName),
        ),
        if (municipalId.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Municipal ID'),
            subtitle: Text(municipalId),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.badge_outlined),
          title: const Text('Account'),
          subtitle: const Text('Municipal crew member'),
        ),
      ],
    );
  }

  Future<void> _logoutFromMenu() async {
    Navigator.of(context).pop();
    await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    final visibleDays = _visibleDays();
    final visibleKeys = visibleDays.map(_dateKey).toSet();
    final heading = switch (_selectedTab) {
      0 => 'Past 7 Days',
      1 => 'Today',
      _ => 'Next 7 Days',
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('DRAINRANK'),
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(_crewName),
                accountEmail: const Text('Municipal Crew Member'),
                currentAccountPicture: const CircleAvatar(
                  child: Icon(Icons.person, size: 34),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Your Profile'),
                onTap: () => _showDetails('Your Profile', _profileDetails()),
              ),
              ListTile(
                leading: const Icon(Icons.history_outlined),
                title: const Text('Your Activity'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CrewActivityPage(currentUserUid: widget.user.uid),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_available_outlined),
                title: const Text('Request Leave'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RequestLeavePage(
                        currentUserUid: widget.user.uid,
                        crewName: _crewName,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Info'),
                onTap: () => _showDetails(
                  'About the App',
                  const Text('View drain-cleaning duties assigned to your municipal account. Tasks update automatically when assignments change.'),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.contact_support_outlined),
                title: const Text('Contact'),
                onTap: () => _showDetails(
                  'Contact',
                  const Text('For account support, assignment issues, or a password reset, contact your Municipal Board office.'),
                ),
              ),
              const Spacer(),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Log Out'),
                onTap: _logoutFromMenu,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history_toggle_off),
            label: 'Past 7 Days',
          ),
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Next 7 Days',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _tasksStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint('Task loading error: ${snapshot.error}');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 44),
                    const SizedBox(height: 12),
                    const Text('Unable to load assigned tasks'),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.error is FirebaseException &&
                          (snapshot.error as FirebaseException).code == 'permission-denied'
                          ? 'Firestore rejected the assigned-tasks query. '
                            'Publish the matching /tasks security rule. '
                            'Project: ${Firebase.app().options.projectId}\n'
                            'Signed-in UID: ${FirebaseAuth.instance.currentUser?.uid ?? widget.user.uid}\n'
                            'Check that assignedToUid contains this UID as an array item.'
                          : 'Check your internet connection and try again.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton(onPressed: _refreshTasks, child: const Text('Retry')),
                  ],
                ),
              ),
            );
          }

          final allAssignedTasks = snapshot.data?.docs ?? [];
          final filtered = allAssignedTasks
              .where((doc) => visibleKeys.contains(doc.data()['dateKey']))
              .toList();
          final byDate = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final doc in filtered) {
            final dateKey = doc.data()['dateKey'] as String;
            byDate.putIfAbsent(dateKey, () => []).add(doc);
          }
          for (final tasks in byDate.values) {
            tasks.sort((a, b) => _timeInMinutes(a.data()['startTime']?.toString())
                .compareTo(_timeInMinutes(b.data()['startTime']?.toString())));
          }

          // The Today tab also includes earlier assignments for which this
          // crew member has not submitted any work update yet.
          final overdueTasks = _selectedTab == 1
              ? allAssignedTasks.where((doc) {
                  final day = _parseTaskDate(doc.data()['dateKey']);
                  return day != null && day.isBefore(_todayOnly());
                }).toList()
              : <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          overdueTasks.sort((a, b) {
            final dayA = _parseTaskDate(a.data()['dateKey'])!;
            final dayB = _parseTaskDate(b.data()['dateKey'])!;
            final byDay = dayA.compareTo(dayB); // oldest overdue task first
            if (byDay != 0) return byDay;
            return _timeInMinutes(a.data()['startTime']?.toString())
                .compareTo(_timeInMinutes(b.data()['startTime']?.toString()));
          });

          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            children: [
              Text('Hello, $_crewName!',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Center(child: CrewCredits(uid: widget.user.uid, compact: true)),
              const SizedBox(height: 12),
              Text(heading,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(
                _selectedTab == 1
                    ? _prettyDate(visibleDays.first)
                    : '${_prettyDate(visibleDays.first)} – ${_prettyDate(visibleDays.last)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (filtered.isEmpty && _selectedTab != 1)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        const Icon(Icons.event_busy_outlined, size: 42),
                        const SizedBox(height: 12),
                        Text('No tasks assigned for $heading', textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        const Text('New assignments will appear here automatically.', textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              if (filtered.isEmpty && _selectedTab == 1)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No tasks assigned for today.', textAlign: TextAlign.center),
                  ),
                ),
              for (final date in visibleDays)
                if (byDate[_dateKey(date)]?.isNotEmpty == true) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                    child: Text(
                      _prettyDate(date),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (var i = 0; i < byDate[_dateKey(date)]!.length; i++)
                    _DrainTaskCard(
                      data: byDate[_dateKey(date)]![i].data(),
                      number: i + 1,
                      taskId: byDate[_dateKey(date)]![i].id,
                      currentUserUid: widget.user.uid,
                      showCredits: true,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TaskDetailsPage(
                            taskId: byDate[_dateKey(date)]![i].id,
                            currentUserUid: widget.user.uid,
                          ),
                        ),
                      ),
                    ),
                ],
              if (_selectedTab == 1) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 18, 4, 10),
                  child: Text('Overdue Tasks',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
                if (overdueTasks.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('No overdue tasks.', textAlign: TextAlign.center),
                  ),
                for (final overdueTask in overdueTasks)
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: overdueTask.reference
                        .collection('workUpdates')
                        .where('submittedByUid', isEqualTo: widget.user.uid)
                        .limit(1)
                        .snapshots(),
                    builder: (context, workSnapshot) {
                      // Hide overdue work once this member has submitted it.
                      if (!workSnapshot.hasData || workSnapshot.hasError ||
                          workSnapshot.data!.docs.isNotEmpty) {
                        return const SizedBox.shrink();
                      }
                      return _DrainTaskCard(
                        data: overdueTask.data(),
                        number: 0,
                        taskId: overdueTask.id,
                        currentUserUid: widget.user.uid,
                        showCredits: true,
                        isOverdue: true,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TaskDetailsPage(
                              taskId: overdueTask.id,
                              currentUserUid: widget.user.uid,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}



/// Personal task history for the past 1, 3, or 6 calendar months.
/// "Done by you" means this member submitted at least one work update;
/// it does NOT mean the administrator marked the shared task Completed.
class CrewActivityPage extends StatefulWidget {
  const CrewActivityPage({super.key, required this.currentUserUid});
  final String currentUserUid;

  @override
  State<CrewActivityPage> createState() => _CrewActivityPageState();
}

class _ActivitySubmissionInfo {
  const _ActivitySubmissionInfo({
    required this.submitted,
    required this.submittedOverdue,
    this.submittedAt,
  });

  final bool submitted;
  final bool submittedOverdue;
  final Timestamp? submittedAt;
}

class _CrewActivityPageState extends State<CrewActivityPage> {
  int _months = 1;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _assignedTasks;
  Future<List<_ActivitySubmissionInfo>>? _submissionFuture;
  String? _submissionKey;

  @override
  void initState() {
    super.initState();
    _assignedTasks = FirebaseFirestore.instance
        .collection('tasks')
        .where('assignedToUid', arrayContains: widget.currentUserUid)
        .snapshots();
  }

  DateTime _earliestDay(DateTime today) {
    // Clamp the date to the final day of the earlier month when necessary.
    final monthStart = DateTime(today.year, today.month - _months, 1);
    final nextMonth = DateTime(monthStart.year, monthStart.month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1)).day;
    return DateTime(monthStart.year, monthStart.month,
        today.day < lastDay ? today.day : lastDay);
  }

  DateTime? _taskDay(Map<String, dynamic> task) {
    final key = task['dateKey'];
    if (key is String) return DateTime.tryParse(key);
    if (key is Timestamp) {
      final date = key.toDate();
      return DateTime(date.year, date.month, date.day);
    }
    return null;
  }

  Future<List<_ActivitySubmissionInfo>> _loadSubmissions(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) async {
    return Future.wait(docs.map((doc) async {
      final result = await doc.reference
          .collection('workUpdates')
          .where('submittedByUid', isEqualTo: widget.currentUserUid)
          .get();
      final overdueDocs = result.docs.where(
        (update) => update.data()['submittedOverdue'] == true,
      ).toList();
      final chosen = overdueDocs.isNotEmpty
          ? overdueDocs.first
          : (result.docs.isNotEmpty ? result.docs.first : null);
      final submittedAtRaw = chosen?.data()['submittedAt'];
      return _ActivitySubmissionInfo(
        submitted: result.docs.isNotEmpty,
        submittedOverdue: overdueDocs.isNotEmpty,
        submittedAt: submittedAtRaw is Timestamp ? submittedAtRaw : null,
      );
    }));
  }

  String _taskTime(Map<String, dynamic> task) {
    final start = (task['startTime'] ?? '').toString().trim();
    final end = (task['endTime'] ?? '').toString().trim();
    if (start.isEmpty) return 'Time not specified';
    return end.isEmpty ? start : '$start - $end';
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final earliest = _earliestDay(todayOnly);
    return Scaffold(
      appBar: AppBar(title: const Text('Your Activity')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users')
            .doc(widget.currentUserUid).collection('creditAwards').snapshots(),
        builder: (context, awardsSnapshot) {
          if (awardsSnapshot.hasError) {
            return Center(child: Text('Unable to load credits: ${awardsSnapshot.error}'));
          }
          final awards = awardsSnapshot.data?.docs ?? [];
          final creditsByTask = <String, int>{};
          final positiveAwardTasks = <String>{};
          final penaltyByTask = <String, int>{};
          var periodCredits = 0;
          final now = DateTime.now();
          final earliestAward = _earliestDay(DateTime(now.year, now.month, now.day));
          for (final award in awards) {
            final data = award.data();
            final value = data['credits'];
            final granted = data['approvedAt'];
            if (value is! int || granted is! Timestamp) continue;
            // Penalties belong to the actual overdue date, even if an admin
            // processes the ledger later. Positive awards use approval date.
            DateTime grantDate;
            if (data['type'] == 'overduePenalty' && data['penaltyDate'] is String) {
              grantDate = DateTime.tryParse(data['penaltyDate'] as String) ?? granted.toDate();
            } else {
              grantDate = granted.toDate();
            }
            final grantedDay = DateTime(grantDate.year, grantDate.month, grantDate.day);
            if (!grantedDay.isBefore(earliestAward) &&
                !grantedDay.isAfter(DateTime(now.year, now.month, now.day))) {
              periodCredits += value;
            }
            final taskId = (data['taskId'] ?? award.id).toString();
            creditsByTask.update(taskId, (current) => current + value, ifAbsent: () => value);
            if (data['type'] == 'overduePenalty' || value < 0) {
              penaltyByTask.update(taskId, (current) => current + value, ifAbsent: () => value);
            } else if (value > 0) {
              positiveAwardTasks.add(taskId);
            }
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _assignedTasks,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Unable to load activity: ${snapshot.error}',
                      textAlign: TextAlign.center),
                ));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data!.docs.where((doc) {
                final day = _taskDay(doc.data());
                return day != null && !day.isBefore(earliest) &&
                    !day.isAfter(todayOnly);
              }).toList();
              docs.sort((a, b) {
                final byDay = _taskDay(b.data())!.compareTo(_taskDay(a.data())!);
                if (byDay != 0) return byDay;
                return _taskTime(b.data()).compareTo(_taskTime(a.data()));
              });

              // Reuse the result while rebuilding; reload when the task set or
              // filter changes. Opening this page again also makes a fresh query.
              final key = '$_months:${docs.map((d) => d.id).join('|')}';
              if (_submissionFuture == null || _submissionKey != key) {
                _submissionKey = key;
                _submissionFuture = _loadSubmissions(docs);
              }
              return FutureBuilder<List<_ActivitySubmissionInfo>>(
                future: _submissionFuture,
                builder: (context, updates) {
                  if (updates.hasError) {
                    return Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Unable to read personal work updates: '
                          '${updates.error}', textAlign: TextAlign.center),
                    ));
                  }
                  final flags = updates.data;
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<int>(
                            style: ButtonStyle(
                              shape: WidgetStateProperty.all(const StadiumBorder()),
                            ),
                            segments: const [
                              ButtonSegment(value: 1, label: Text('1 Month')),
                              ButtonSegment(value: 3, label: Text('3 Months')),
                              ButtonSegment(value: 6, label: Text('6 Months')),
                            ],
                            selected: {_months},
                            onSelectionChanged: (selection) {
                              setState(() => _months = selection.first);
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: _ActivitySummaryCard(
                              label: 'Tasks assigned',
                              count: docs.length,
                              icon: Icons.assignment_outlined,
                            )),
                            const SizedBox(width: 10),
                            Expanded(child: _ActivitySummaryCard(
                              label: 'Submitted',
                              count: flags == null
                                  ? null
                                  : flags.where((value) => value.submitted).length,
                              icon: Icons.task_alt,
                            )),
                            const SizedBox(width: 10),
                            Expanded(child: _ActivitySummaryCard(
                              label: 'Net credits',
                              count: awardsSnapshot.hasData ? periodCredits : null,
                              icon: Icons.workspace_premium_outlined,
                            )),
                          ]),

                        ],
                      ),
                    ),
                    if (flags == null)
                      const Expanded(child: Center(child: CircularProgressIndicator()))
                    else if (docs.isEmpty)
                      const Expanded(child: Center(child: Text(
                        'No assigned tasks in this period.',
                      )))
                    else
                      Expanded(child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final task = doc.data();
                          final day = _taskDay(task)!;
                          final submission = flags[index];
                          final submitted = submission.submitted;
                          final isPastDate = DateTime(day.year, day.month, day.day)
                              .isBefore(todayOnly);
                          final hasAward = positiveAwardTasks.contains(doc.id);
                          final penalty = penaltyByTask[doc.id] ?? 0;
                          final taskCredits = creditsByTask[doc.id] ?? 0;
                          final approvalLabel = hasAward
                              ? 'Approved'
                              : submitted ? 'Awaiting approval' : penalty < 0 ? 'Penalty applied' : 'Pending';
                          final statusTextStyle = Theme.of(context).textTheme.bodyMedium;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(builder: (_) => TaskDetailsPage(
                                  taskId: doc.id,
                                  currentUserUid: widget.currentUserUid,
                                )),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Use the full card width so the time's right edge
                                    // lines up with the approval label below it.
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            (task['title'] ?? 'Assigned task').toString(),
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 155),
                                          child: Text(
                                            _taskTime(task),
                                            textAlign: TextAlign.right,
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(_prettyDate(day), style: statusTextStyle),
                                    if (submission.submittedOverdue) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Overdue · Submitted${submission.submittedAt == null ? '' : ' ${_prettyDate(submission.submittedAt!.toDate())}'}',
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: const Color(0xFFD97706),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Text(
                                      'Shared status: ${task['status'] ?? 'Pending'}',
                                      style: statusTextStyle,
                                    ),
                                    // Omit the redundant personal-update status for
                                    // past dates. On today's task use the same font as
                                    // the shared status for consistency.
                                    if (!isPastDate)
                                      Text(
                                        submitted
                                            ? 'Your work update: Submitted'
                                            : 'Your work update: Pending',
                                        style: statusTextStyle,
                                      ),
                                    const SizedBox(height: 10),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (hasAward) Row(children: [
                                              Icon(Icons.workspace_premium_outlined, size: 18, color: const Color(0xFFF59E0B)),
                                              const SizedBox(width: 5),
                                              Text('+${creditsByTask[doc.id] != null && penalty < 0 ? taskCredits - penalty : taskCredits} credits',
                                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                            ]),
                                            if (penalty < 0) Row(children: [
                                              Icon(Icons.trending_down, size: 18, color: const Color(0xFFB91C1C)),
                                              const SizedBox(width: 5),
                                              Text('$penalty credits', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: const Color(0xFFB91C1C))),
                                            ]),
                                            if (!hasAward && penalty == 0) Row(children: [
                                              Icon(Icons.schedule_outlined, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                              const SizedBox(width: 5),
                                              const Text('0 credits', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                            ]),
                                          ],
                                        )),
                                        const SizedBox(width: 8),
                                        Text(
                                          approvalLabel,
                                          textAlign: TextAlign.right,
                                          style: TextStyle(
                                            color: hasAward ? const Color(0xFF059669) : penalty < 0 ? const Color(0xFFB91C1C)
                                                : Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      )),
                  ]);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ActivitySummaryCard extends StatelessWidget {
  const _ActivitySummaryCard({
    required this.label, required this.count, required this.icon,
  });
  final String label;
  final int? count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(count?.toString() ?? '...',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              )),
          Text(label, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

List<Map<String, dynamic>> _sampleTasksForDate(String dateKey) {
// Demonstration data only: these tasks are not written to Firestore.
  return [
    {
      'title': 'Clean roadside drain',
      'startTime': '08:00 AM',
      'endTime': '09:30 AM',
      'location': 'Ward 12, near Community Park',
      'description': 'Remove waste and blockage. Keep the footpath clear.',
      'status': 'Pending',
      'dateKey': dateKey,
    },
    {
      'title': 'Remove drain blockage',
      'startTime': '10:00 AM',
      'endTime': '11:00 AM',
      'location': 'Main Market Road, opposite Bus Stop',
      'description': 'Check water flow and collect removed waste safely.',
      'status': 'In Progress',
      'dateKey': dateKey,
    },
    {
      'title': 'Inspect and rinse drain',
      'startTime': '01:00 PM',
      'endTime': '02:00 PM',
      'location': 'Lane 4, Shastri Nagar',
      'description': 'Confirm the drain is flowing freely after cleaning.',
      'status': 'Completed',
      'dateKey': dateKey,
    },
  ];
}

class _DemoTaskPreview extends StatelessWidget {
  const _DemoTaskPreview({
    required this.tasks,
    required this.firebaseError,
  });

  final List<Map<String, dynamic>> tasks;
  final bool firebaseError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: colors.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                firebaseError ? Icons.cloud_off_outlined : Icons.visibility_outlined,
                color: colors.onTertiaryContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  firebaseError
                      ? 'Showing sample tasks because Firebase tasks could not be loaded. These are demo examples, not real assignments. Check Firestore rules, the tasks collection, and the debug console.'
                      : 'Sample preview only — these example tasks are not saved in Firebase. Real tasks assigned by the admin will appear here.',
                  style: TextStyle(color: colors.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < tasks.length; i++)
          _DrainTaskCard(data: tasks[i], number: i + 1),
      ],
    );
  }
}

class _DateTab extends StatelessWidget {
  const _DateTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.surfaceContainerHighest : colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 7),
              Icon(icon, size: 23),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskMessage extends StatelessWidget {
  const _TaskMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
        child: Column(
          children: [
            Icon(icon, size: 46),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 7),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// Compact list item: only title and scheduled time.
class _DrainTaskCard extends StatelessWidget {
  const _DrainTaskCard({
    required this.data,
    required this.number,
    this.onTap,
    this.taskId,
    this.currentUserUid,
    this.showCredits = false,
    this.isOverdue = false,
  });

  final Map<String, dynamic> data;
  final int number;
  final VoidCallback? onTap;
  final String? taskId;
  final String? currentUserUid;
  final bool showCredits;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? 'Clean assigned drain').toString();
    final start = (data['startTime'] ?? '').toString();
    final end = (data['endTime'] ?? '').toString();
    final time = start.isEmpty
        ? 'Time not specified'
        : (end.isEmpty ? start : '$start – $end');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        leading: const CircleAvatar(child: Icon(Icons.water_drop_outlined)),
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(time, style: Theme.of(context).textTheme.bodySmall),
            if (isOverdue)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'OVERDUE · Assigned ${_taskDateLabel(data['dateKey'])}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFB91C1C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Warning: a daily credit deduction may apply until work is submitted.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFB91C1C)),
                  ),
                ]),
              ),
            if (taskId != null && currentUserUid != null) ...[
              const SizedBox(height: 4),
              Text(
                "Shared task status: ${(data['status'] ?? 'Pending').toString()}",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (showCredits) ...[
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUserUid)
                      .collection('creditAwards')
                      .where('taskId', isEqualTo: taskId)
                      .snapshots(),
                  builder: (context, awardSnapshot) {
                    if (awardSnapshot.hasError) {
                      return Text('Credits unavailable', style: Theme.of(context).textTheme.bodySmall);
                    }
                    var total = 0;
                    var penaltyTotal = 0;
                    for (final entry in awardSnapshot.data?.docs ?? const []) {
                      final value = entry.data()['credits'];
                      if (value is! int) continue;
                      total += value;
                      if (entry.data()['type'] == 'overduePenalty') penaltyTotal += value;
                    }
                    final rate = data['dailyOverdueDeduction'] is int
                        ? data['dailyOverdueDeduction'] as int : 0;
                    final day = _parseTaskDate(data['dateKey']);
                    final elapsedDays = day != null && isOverdue
                        ? _todayOnly().difference(day).inDays : 0;
                    final estimatedPenalty = rate * elapsedDays;
                    if (isOverdue && penaltyTotal < 0) {
                      return Row(children: [
                        Icon(Icons.trending_down, size: 18, color: const Color(0xFFB91C1C)),
                        const SizedBox(width: 5),
                        Text('$penaltyTotal credits', style: TextStyle(fontWeight: FontWeight.w700, color: const Color(0xFFB91C1C))),
                      ]);
                    }
                    if (isOverdue && estimatedPenalty > 0) {
                      return Row(children: [
                        Icon(Icons.trending_down, size: 18, color: const Color(0xFFB91C1C)),
                        const SizedBox(width: 5),
                        Text('−$estimatedPenalty credits (pending)', style: TextStyle(fontWeight: FontWeight.w700, color: const Color(0xFFB91C1C))),
                      ]);
                    }
                    if (total < 0) {
                      return Row(children: [
                        Icon(Icons.trending_down, size: 18, color: const Color(0xFFB91C1C)),
                        const SizedBox(width: 5),
                        Text('$total credits', style: TextStyle(fontWeight: FontWeight.w700, color: const Color(0xFFB91C1C))),
                      ]);
                    }
                    return Row(children: [
                      Icon(total > 0 ? Icons.workspace_premium_outlined : Icons.schedule_outlined,
                          size: 18, color: total > 0 ? const Color(0xFFF59E0B) : Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text(total > 0 ? '+$total credits' : '0 credits', style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]);
                  },
                ),
              ],
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('tasks')
                    .doc(taskId)
                    .collection('workUpdates')
                    .where('submittedByUid', isEqualTo: currentUserUid)
                    .limit(1)
                    .snapshots(),
                builder: (context, snapshot) {
                  final submitted = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
                  return Text(
                    submitted ? 'Your image upload: Submitted' : 'Your image upload: Pending',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: submitted ? const Color(0xFF059669) : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      ),
    );
  }
}

DateTime? _parseTaskDate(dynamic rawDate) {
  DateTime? parsed;
  if (rawDate is String) parsed = DateTime.tryParse(rawDate);
  if (rawDate is Timestamp) parsed = rawDate.toDate();
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

DateTime _todayOnly() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

bool isScheduledToday(dynamic dateKey) {
  final day = _parseTaskDate(dateKey);
  return day != null && day == _todayOnly();
}

bool isOverdueTaskDate(dynamic dateKey) {
  final day = _parseTaskDate(dateKey);
  return day != null && day.isBefore(_todayOnly());
}

bool isTodayOrOverdueTaskDate(dynamic dateKey) {
  final day = _parseTaskDate(dateKey);
  return day != null && !day.isAfter(_todayOnly());
}

/// Explicit task edit boundaries written by the administrator.
/// A task without these boundaries is read-only for server-enforced uploads.
bool hasEditWindow(Map<String, dynamic> task) =>
    task['workWindowStart'] is Timestamp && task['workWindowEnd'] is Timestamp;

/// One shared Firestore task document can be assigned to multiple crew UIDs.
/// Each crew member's photo submission is stored separately in `workUpdates`.
/// Applies idempotent, admin-authorized daily overdue deductions from each task's
/// `dailyOverdueDeduction` field. Call explicitly from the admin review screen.
/// A separate immutable ledger document is created for each crew/task/day.
Future<int> processOverdueDeductionsForAdmin(String adminUid) async {
  final db = FirebaseFirestore.instance;
  final today = _todayOnly();
  final tasks = await db.collection('tasks').get();
  var createdCount = 0;

  for (final taskDoc in tasks.docs) {
    final task = taskDoc.data();
    final taskDay = _parseTaskDate(task['dateKey']);
    final rate = task['dailyOverdueDeduction'];
    final assignedRaw = task['assignedToUid'];
    if (taskDay == null || !taskDay.isBefore(today) || rate is! int || rate <= 0 || assignedRaw is! List) {
      continue;
    }

    for (final uid in assignedRaw.whereType<String>()) {
      final submissions = await taskDoc.reference.collection('workUpdates')
          .where('submittedByUid', isEqualTo: uid).get();
      var cutoffDay = today;
      if (submissions.docs.isNotEmpty) {
        DateTime? firstSubmissionDay;
        for (final submission in submissions.docs) {
          final submittedAt = submission.data()['submittedAt'];
          if (submittedAt is! Timestamp) continue;
          final timestamp = submittedAt.toDate();
          final day = DateTime(timestamp.year, timestamp.month, timestamp.day);
          if (firstSubmissionDay == null || day.isBefore(firstSubmissionDay)) {
            firstSubmissionDay = day;
          }
        }
        if (firstSubmissionDay != null) cutoffDay = firstSubmissionDay;
      }
      if (!cutoffDay.isAfter(taskDay)) continue;

      for (var penaltyDay = taskDay.add(const Duration(days: 1));
          !penaltyDay.isAfter(cutoffDay);
          penaltyDay = penaltyDay.add(const Duration(days: 1))) {
        final dayKey = _dateKey(penaltyDay);
        final penaltyId = 'overdue_${taskDoc.id}_$dayKey';
        final penaltyRef = db.collection('users').doc(uid)
            .collection('creditAwards').doc(penaltyId);
        final created = await db.runTransaction<bool>((tx) async {
          final prior = await tx.get(penaltyRef);
          if (prior.exists) return false;
          tx.set(penaltyRef, {
            'taskId': taskDoc.id,
            'taskTitle': (task['title'] ?? 'Assigned task').toString(),
            'crewUid': uid,
            'credits': -rate,
            'type': 'overduePenalty',
            'penaltyDate': dayKey,
            'dailyRate': rate,
            'approvedByUid': adminUid,
            'approvedAt': FieldValue.serverTimestamp(),
          });
          return true;
        });
        if (created) createdCount++;
      }
    }
  }
  return createdCount;
}

String _taskDateLabel(dynamic rawDate) {
  if (rawDate is String) {
    final parsed = DateTime.tryParse(rawDate);
    if (parsed != null) return _prettyDate(parsed);
  }
  if (rawDate is Timestamp) return _prettyDate(rawDate.toDate());
  return 'Date not specified';
}

/// Live, per-crew admin award display for this task.
class _TaskAwardCredits extends StatelessWidget {
  const _TaskAwardCredits({required this.taskId, required this.uid});
  final String taskId;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid)
          .collection('creditAwards').where('taskId', isEqualTo: taskId).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('Credits unavailable');
        var total = 0;
        for (final doc in snapshot.data?.docs ?? const []) {
          final amount = doc.data()['credits'];
          if (amount is int) total += amount;
        }
        final isPenalty = total < 0;
        final hasAward = total > 0;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isPenalty ? Icons.trending_down : hasAward
                ? Icons.workspace_premium_outlined : Icons.schedule_outlined,
            size: 20,
            color: isPenalty ? const Color(0xFFB91C1C) : hasAward
                ? const Color(0xFFF59E0B) : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            total < 0 ? '$total credits' : hasAward ? '+$total credits' : '0 credits',
            style: TextStyle(fontWeight: FontWeight.bold,
                color: isPenalty ? const Color(0xFFB91C1C) : null),
          ),
        ]);
      },
    );
  }
}

class _GeoMetadataRow extends StatelessWidget {
  const _GeoMetadataRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 92, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
      Expanded(child: Text(value)),
    ]),
  );
}

String _formatCapturedAt(dynamic value) {
  if (value is Timestamp) {
    final date = value.toDate();
    return '${_prettyDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  return 'Not recorded';
}

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
class LiveCameraCapture {
  const LiveCameraCapture({required this.image, required this.capturedAt});
  final XFile image;
  final DateTime capturedAt;
}

/// In-app camera preview on Android and supported browsers.
/// Never offers a gallery/file-picker fallback for work evidence.
class LiveWorkCameraPage extends StatefulWidget {
  const LiveWorkCameraPage({super.key});

  @override
  State<LiveWorkCameraPage> createState() => _LiveWorkCameraPageState();
}

class _LiveWorkCameraPageState extends State<LiveWorkCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _capturing = false;
  String? _error;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera available on this device or browser.');
      }
      final camera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Camera unavailable: $e';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
// Avoid leaving the camera active when the app goes into the background.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller?.dispose();
      _controller = null;
      if (mounted) setState(() => _initializing = true);
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initializeCamera();
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_capturing || controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final image = await controller.takePicture();
      final capturedAt = DateTime.now();
      if (!mounted) return;
      Navigator.of(context).pop(
        LiveCameraCapture(image: image, capturedAt: capturedAt),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = 'Photo capture failed: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Live Work Camera')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, textAlign: TextAlign.center),
                )
                    : _initializing || controller == null ||
                    !controller.value.isInitialized
                    ? const CircularProgressIndicator()
                    : AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: CameraPreview(controller),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('Take a new work photo. GPS coordinates and capture time are embedded in the JPG EXIF metadata.'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: FilledButton.icon(
                onPressed: _error != null || _initializing || _capturing
                    ? null
                    : _capture,
                icon: const Icon(Icons.camera_alt),
                label: Text(_capturing ? 'Capturing...' : 'Capture photo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskDetailRow extends StatelessWidget {
  const _TaskDetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 9),
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}
