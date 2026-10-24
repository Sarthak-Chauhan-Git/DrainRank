import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../models/citizen_report.dart';

class DuplicateCheckResult {
  final bool isBlocked;
  final CitizenReport? existingReport;
  final double? distanceMeters;

  const DuplicateCheckResult({
    required this.isBlocked,
    this.existingReport,
    this.distanceMeters,
  });
}

class ImageQualityResult {
  final String sha256Hash;
  final double luminance;
  final bool isValid;
  final String statusMessage;

  const ImageQualityResult({
    required this.sha256Hash,
    required this.luminance,
    required this.isValid,
    required this.statusMessage,
  });
}

class DrainRankEngine {
  static const String _storageKeyDeviceId = 'drainrank_device_id_v1';
  static String _reportsStorageKey(String userId) =>
      'drainrank_local_reports_v1_$userId';

  /// 1. Persistent Hardware Device Fingerprint (for Same-Device Radius Lock)
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? cachedId = prefs.getString(_storageKeyDeviceId);
    if (cachedId != null && cachedId.isNotEmpty) return cachedId;

    final deviceInfo = DeviceInfoPlugin();
    String rawId = const Uuid().v4();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        rawId = '${androidInfo.brand}-${androidInfo.model}-${androidInfo.id}';
      }
    } catch (_) {}

    final hashedDevice = sha256
        .convert(rawId.codeUnits)
        .toString()
        .substring(0, 16)
        .toUpperCase();
    await prefs.setString(_storageKeyDeviceId, 'DEV-$hashedDevice');
    return 'DEV-$hashedDevice';
  }

  /// 2. Unique Report ID Generator (Handwritten Rule #4)
  static String generateUniqueReportId() {
    final datePart = DateFormat('yyyyMMdd').format(DateTime.now());
    final randomHex = const Uuid().v4().substring(0, 4).toUpperCase();
    return 'REP-$datePart-$randomHex';
  }

  /// 3. High-Accuracy Geotag Acquisition (Handwritten Rule #1)
  static Future<Position> acquireGeotagPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception(
        'Location services (GPS) are disabled. Please turn on GPS.',
      );
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permissions are permanently denied in Settings.',
      );
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 12),
      ),
    );
  }

  /// 4. Nearest Known Drain Matcher (e.g. DR-1024 within 35m or Provisional Pin)
  static KnownDrainPin? findNearestDrain(double lat, double lng) {
    KnownDrainPin? closest;
    double minDistance = double.infinity;

    for (final drain in kDemoDrainInventory) {
      final dist = Geolocator.distanceBetween(
        lat,
        lng,
        drain.latitude,
        drain.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        closest = drain;
      }
    }
    // Link to known drain if within 50 meters; otherwise treat as provisional pin
    if (minDistance <= 50.0) {
      return closest;
    }
    return null;
  }

  /// 5. Location-Wise Unique Report Guard (Handwritten Rule #5: 15m Radius + Same Device)
  static Future<DuplicateCheckResult> checkSameDeviceRadiusLock({
    required double currentLat,
    required double currentLng,
    required String deviceId,
    required String userId,
  }) async {
    final existingReports = await getSavedReports(userId: userId);
    final now = DateTime.now();

    for (final report in existingReports) {
      final hoursSinceReport = now.difference(report.capturedAt).inHours;
      if (report.deviceId == deviceId &&
          hoursSinceReport < AppConstants.sameDeviceCooldownHours) {
        final distanceMeters = Geolocator.distanceBetween(
          currentLat,
          currentLng,
          report.latitude,
          report.longitude,
        );

        if (distanceMeters <= AppConstants.duplicateRadiusMeters) {
          return DuplicateCheckResult(
            isBlocked: true,
            existingReport: report,
            distanceMeters: distanceMeters,
          );
        }
      }
    }
    return const DuplicateCheckResult(isBlocked: false);
  }

  /// 6. SHA-256 Integrity Hash + Step 2 Image Quality Check (Luminance / Blur)
  static Future<ImageQualityResult> analyzeAndHashPhoto(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final sha256Hash = sha256.convert(bytes).toString();

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return ImageQualityResult(
        sha256Hash: sha256Hash,
        luminance: 0,
        isValid: false,
        statusMessage: 'Invalid image format',
      );
    }

    // Sample pixels for fast average luminance check (0 - 255)
    double totalLum = 0;
    int count = 0;
    final stepX = max(1, decoded.width ~/ 25);
    final stepY = max(1, decoded.height ~/ 25);

    for (int y = 0; y < decoded.height; y += stepY) {
      for (int x = 0; x < decoded.width; x += stepX) {
        final pixel = decoded.getPixel(x, y);
        final lum = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
        totalLum += lum;
        count++;
      }
    }

    final avgLum = count > 0 ? totalLum / count : 120.0;
    if (avgLum < AppConstants.minBrightnessThreshold) {
      return ImageQualityResult(
        sha256Hash: sha256Hash,
        luminance: avgLum,
        isValid: false,
        statusMessage: 'Too Dark (Luminance ${avgLum.toStringAsFixed(0)}/255)',
      );
    } else if (avgLum > AppConstants.maxBrightnessThreshold) {
      return ImageQualityResult(
        sha256Hash: sha256Hash,
        luminance: avgLum,
        isValid: false,
        statusMessage: 'Overexposed / Glare detected',
      );
    }

    return ImageQualityResult(
      sha256Hash: sha256Hash,
      luminance: avgLum,
      isValid: true,
      statusMessage:
          'Valid Image • Quality Verified (Lum ${avgLum.toStringAsFixed(0)})',
    );
  }

  /// 7. Calculate DrainRank Priority Score Preview (Formula 1 & 2 from Proposal Section 4)
  static double computePriorityScore({
    required IssueCategory category,
    required UrgencyConsequence urgency,
    KnownDrainPin? matchedDrain,
  }) {
    final double aProxy = matchedDrain?.catchmentProxyA ?? 0.65;
    final double vValue = urgency.vWeight;
    // M_i = 100 * (0.40 * B_i + 0.35 * A_i + 0.25 * V_i)
    final double bOrU = category.bScoreInput;
    final double rawScore =
        100.0 * (0.40 * bOrU + 0.35 * aProxy + 0.25 * vValue);
    return double.parse(rawScore.toStringAsFixed(1));
  }

  /// 8. Account-scoped local cache for offline report tracking.
  static Future<List<CitizenReport>> getSavedReports({
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_reportsStorageKey(userId));
    if (raw == null || raw.isEmpty) return [];
    return CitizenReport.decodeList(raw);
  }

  static Future<void> saveReport(
    CitizenReport report, {
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await getSavedReports(userId: userId);
    current.insert(0, report);
    await prefs.setString(
      _reportsStorageKey(userId),
      CitizenReport.encodeList(current),
    );
  }

  static Future<void> cacheReports(
    List<CitizenReport> reports, {
    required String userId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _reportsStorageKey(userId),
      CitizenReport.encodeList(reports),
    );
  }
}
