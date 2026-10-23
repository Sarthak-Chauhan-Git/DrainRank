class AppConstants {
  static const String appName = 'Swachh Pravah';
  static const String wardName = 'Ward 12 • Storm Water Division';

  // Handwritten Note & Proposal Section 3.3 Rules:
  // 15.0 meters pilot default tolerance for same-drain & anti-spam radius lock
  static const double duplicateRadiusMeters = 15.0;
  static const int sameDeviceCooldownHours = 24;

  // Image Pre-validation Thresholds (Step 2 of Workflow Poster)
  static const double minBrightnessThreshold = 35.0; // 0-255 luminance
  static const double maxBrightnessThreshold = 245.0;
}

class KnownDrainPin {
  final String drainId;
  final String name;
  final double latitude;
  final double longitude;
  final double catchmentProxyA;
  final double defaultConsequenceV;
  final String vReason;

  const KnownDrainPin({
    required this.drainId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.catchmentProxyA,
    required this.defaultConsequenceV,
    required this.vReason,
  });
}
enum HighUrgencyPlaceType {
  hospital,
  school,
  emergencyFacility,
}

class HighUrgencyPlace {
  final String name;
  final HighUrgencyPlaceType type;
  final double latitude;
  final double longitude;

  const HighUrgencyPlace({
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
  });
}
// Pre-loaded drains from Poster (DR-1024) & Proposal Case Study (Section 5.1)
const List<KnownDrainPin> kDemoDrainInventory = [
  KnownDrainPin(
    drainId: 'DR-1024',
    name: 'Hospital Road Main Inlet',
    latitude: 28.9845,
    longitude: 77.7064,
    catchmentProxyA: 1.00,
    defaultConsequenceV: 1.0,
    vReason: 'Hospital access route',
  ),
  KnownDrainPin(
    drainId: 'DR-0876',
    name: 'Market Area Sector B',
    latitude: 28.9852,
    longitude: 77.7071,
    catchmentProxyA: 0.75,
    defaultConsequenceV: 0.4,
    vReason: 'Residential / Market street',
  ),
  KnownDrainPin(
    drainId: 'DR-0653',
    name: 'Main Street Underpass Approach',
    latitude: 28.9838,
    longitude: 77.7055,
    catchmentProxyA: 0.60,
    defaultConsequenceV: 0.8,
    vReason: 'Underpass approach',
  ),
];