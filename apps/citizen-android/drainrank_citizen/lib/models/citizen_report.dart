import 'dart:convert';

enum IssueCategory {
  blockedDrain(
    label: 'Blocked Drain',
    code: 'BLOCKED_DRAIN',
    bScoreInput: 1.0,
    triageQueue: 'Cleaning Queue',
  ),
  waterlogging(
    label: 'Waterlogging',
    code: 'WATERLOGGING',
    bScoreInput: 1.0,
    triageQueue: 'Cleaning Queue',
  ),
  overflow(
    label: 'Overflow',
    code: 'OVERFLOW',
    bScoreInput: 1.0,
    triageQueue: 'Cleaning Queue',
  ),
  needsInspection(
    label: 'Needs Inspection',
    code: 'NEEDS_INSPECTION',
    bScoreInput: 0.5, // Routes to Inspection Queue (U = 1.0)
    triageQueue: 'Inspection Queue',
  ),
  other(
    label: 'Other',
    code: 'OTHER',
    bScoreInput: 0.5,
    triageQueue: 'Inspection Queue',
  );

  final String label;
  final String code;
  final double bScoreInput;
  final String triageQueue;

  const IssueCategory({
    required this.label,
    required this.code,
    required this.bScoreInput,
    required this.triageQueue,
  });
}

enum UrgencyConsequence {
  standardResidential(
    label: 'Standard Street / Lane',
    vWeight: 0.4,
    isUrgentFlag: false,
  ),
  importantRoute(
    label: 'Main Road / Market Access',
    vWeight: 0.7,
    isUrgentFlag: true,
  ),
  underpassApproach(
    label: 'Underpass / Low-Lying Choke Point',
    vWeight: 0.8,
    isUrgentFlag: true,
  ),
  criticalHospitalSchool(
    label: 'Hospital / School / Emergency Route',
    vWeight: 1.0,
    isUrgentFlag: true,
  );

  final String label;
  final double vWeight;
  final bool isUrgentFlag;

  const UrgencyConsequence({
    required this.label,
    required this.vWeight,
    required this.isUrgentFlag,
  });
}

// Exact 5 statuses from Step 8 of the DrainRank End-to-End Workflow Poster
enum ReportWorkflowStatus {
  complaintReceived(
    stepIndex: 0,
    title: 'Complaint Received',
    subtitle: 'Geotagged report logged & assigned a unique ID.',
  ),
  underVerification(
    stepIndex: 1,
    title: 'Under Verification',
    subtitle: 'Backend checked image quality, GPS & duplicate radius.',
  ),
  workAssigned(
    stepIndex: 2,
    title: 'Work Assigned',
    subtitle: 'Ranked in priority queue and dispatched to field crew.',
  ),
  cleaningCompleted(
    stepIndex: 3,
    title: 'Cleaning Completed',
    subtitle: 'Post-cleaning photo verified against location & timestamp.',
  ),
  underMonitoring(
    stepIndex: 4,
    title: 'Under Monitoring',
    subtitle: 'Awaiting post-rain outcome evaluation.',
  );

  final int stepIndex;
  final String title;
  final String subtitle;

  const ReportWorkflowStatus({
    required this.stepIndex,
    required this.title,
    required this.subtitle,
  });
}

class CitizenReport {
  final String reportId; // Unique Report ID (e.g., REP-20261016-8F3A)
  final String deviceId; // Hardware fingerprint for same-device radius lock
  final String linkedDrainId; // e.g., DR-1024 or PROVISIONAL-PIN
  final double latitude;
  final double longitude;
  final double gpsAccuracyMeters;
  final DateTime capturedAt; // FR-02 separate capture timestamp
  final DateTime uploadedAt; // FR-02 separate upload timestamp
  final String imagePath;
  final String? imageUrl;
  final String imageSha256Hash; // Section 3.3 integrity hash
  final bool imageQualityPassed;
  final double imageLuminance;
  final IssueCategory issueCategory;
  final String? aiSuggestedCategory;
  final double? aiConfidence;
  final bool isUrgentFlagged; // Handwritten note: Urgency Flag
  final UrgencyConsequence urgencyConsequence;
  final String description;
  final ReportWorkflowStatus status;
  final double estimatedPriorityScore;

  const CitizenReport({
    required this.reportId,
    required this.deviceId,
    required this.linkedDrainId,
    required this.latitude,
    required this.longitude,
    required this.gpsAccuracyMeters,
    required this.capturedAt,
    required this.uploadedAt,
    required this.imagePath,
    this.imageUrl,
    required this.imageSha256Hash,
    required this.imageQualityPassed,
    required this.imageLuminance,
    required this.issueCategory,
    this.aiSuggestedCategory,
    this.aiConfidence,
    required this.isUrgentFlagged,
    required this.urgencyConsequence,
    required this.description,
    required this.status,
    required this.estimatedPriorityScore,
  });

  Map<String, dynamic> toJson() => {
    'report_id': reportId,
    'device_id': deviceId,
    'linked_drain_id': linkedDrainId,
    'latitude': latitude,
    'longitude': longitude,
    'gps_accuracy_meters': gpsAccuracyMeters,
    'captured_at': capturedAt.toIso8601String(),
    'uploaded_at': uploadedAt.toIso8601String(),
    'image_path': imagePath,
    'image_url': imageUrl,
    'image_sha256_hash': imageSha256Hash,
    'image_quality_passed': imageQualityPassed,
    'image_luminance': imageLuminance,
    'issue_category': issueCategory.name,
    'ai_suggested_category': aiSuggestedCategory,
    'ai_confidence': aiConfidence,
    'is_urgent_flagged': isUrgentFlagged,
    'urgency_consequence': urgencyConsequence.name,
    'description': description,
    'status': status.name,
    'estimated_priority_score': estimatedPriorityScore,
  };

  factory CitizenReport.fromJson(Map<String, dynamic> json) => CitizenReport(
    reportId: json['report_id'] as String,
    deviceId: json['device_id'] as String,
    linkedDrainId: json['linked_drain_id'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    gpsAccuracyMeters: (json['gps_accuracy_meters'] as num).toDouble(),
    capturedAt: DateTime.parse(json['captured_at'] as String),
    uploadedAt: DateTime.parse(json['uploaded_at'] as String),
    imagePath: json['image_path'] as String,
    imageUrl: json['image_url'] as String?,
    imageSha256Hash: json['image_sha256_hash'] as String,
    imageQualityPassed: json['image_quality_passed'] as bool,
    imageLuminance: (json['image_luminance'] as num).toDouble(),
    issueCategory: IssueCategory.values.firstWhere(
      (e) => e.name == json['issue_category'],
      orElse: () => IssueCategory.blockedDrain,
    ),
    aiSuggestedCategory: json['ai_suggested_category'] as String?,
    aiConfidence: (json['ai_confidence'] as num?)?.toDouble(),
    isUrgentFlagged: json['is_urgent_flagged'] as bool,
    urgencyConsequence: UrgencyConsequence.values.firstWhere(
      (e) => e.name == json['urgency_consequence'],
      orElse: () => UrgencyConsequence.standardResidential,
    ),
    description: json['description'] as String,
    status: ReportWorkflowStatus.values.firstWhere(
      (e) => e.name == json['status'],
      orElse: () => ReportWorkflowStatus.complaintReceived,
    ),
    estimatedPriorityScore: (json['estimated_priority_score'] as num)
        .toDouble(),
  );

  static String encodeList(List<CitizenReport> reports) =>
      jsonEncode(reports.map((r) => r.toJson()).toList());

  static List<CitizenReport> decodeList(String encoded) {
    final List<dynamic> list = jsonDecode(encoded) as List<dynamic>;
    return list
        .map((item) => CitizenReport.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
