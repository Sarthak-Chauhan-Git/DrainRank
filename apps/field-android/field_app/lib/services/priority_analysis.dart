import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

const double fieldPriorityRadiusMeters = 500;

class FieldNearbyPlace {
  const FieldNearbyPlace({
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
  });

  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final double distanceMeters;
}

class FieldDrainMatch {
  const FieldDrainMatch({
    required this.drainId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.catchmentProxy,
  });

  final String drainId;
  final String name;
  final double latitude;
  final double longitude;
  final double catchmentProxy;
}

class FieldPriorityAnalysis {
  const FieldPriorityAnalysis({
    required this.score,
    required this.urgent,
    required this.nearbyPlaces,
    required this.matchedDrain,
  });

  final double score;
  final bool urgent;
  final List<FieldNearbyPlace> nearbyPlaces;
  final FieldDrainMatch? matchedDrain;

  FieldNearbyPlace? get nearestPlace =>
      nearbyPlaces.isEmpty ? null : nearbyPlaces.first;
}

class FieldPriorityAnalyzer {
  static const _apiKey = String.fromEnvironment('GEOAPIFY_API_KEY');
  static const _placesUrl = 'https://api.geoapify.com/v2/places';
  static const _facilityCategories = {
    'healthcare.hospital': 'hospital',
    'education.school': 'school',
    'education.university': 'university',
    'education.college': 'college',
    'service.police': 'police station',
    'service.fire_station': 'fire station',
  };

  static const _knownDrains = [
    FieldDrainMatch(
      drainId: 'DR-1024',
      name: 'Hospital Road Main Inlet',
      latitude: 28.9845,
      longitude: 77.7064,
      catchmentProxy: 1.00,
    ),
    FieldDrainMatch(
      drainId: 'DR-0876',
      name: 'Market Area Sector B',
      latitude: 28.9852,
      longitude: 77.7071,
      catchmentProxy: 0.75,
    ),
    FieldDrainMatch(
      drainId: 'DR-0653',
      name: 'Main Street Underpass Approach',
      latitude: 28.9838,
      longitude: 77.7055,
      catchmentProxy: 0.60,
    ),
  ];

  Future<FieldPriorityAnalysis> analyze({
    required double latitude,
    required double longitude,
    required String issueCategory,
  }) async {
    if (_apiKey.isEmpty) {
      throw StateError(
        'Geoapify API key is missing. Build with '
        '--dart-define=GEOAPIFY_API_KEY=YOUR_KEY.',
      );
    }

    final places = await _fetchNearbyPlaces(
      latitude: latitude,
      longitude: longitude,
    );
    final drain = _findNearestDrain(latitude, longitude);
    final urgent = places.isNotEmpty;
    return FieldPriorityAnalysis(
      score: priorityScore(
        issueCategory: issueCategory,
        urgent: urgent,
        matchedDrain: drain,
      ),
      urgent: urgent,
      nearbyPlaces: places,
      matchedDrain: drain,
    );
  }

  static double priorityScore({
    required String issueCategory,
    required bool urgent,
    FieldDrainMatch? matchedDrain,
  }) {
    final categoryWeight = switch (issueCategory) {
      'blocked_drain' || 'waterlogging' || 'overflow' => 1.0,
      _ => 0.5,
    };
    final catchmentWeight = matchedDrain?.catchmentProxy ?? 0.65;
    final urgencyWeight = urgent ? 1.0 : 0.4;
    final score =
        100 *
        (0.40 * categoryWeight + 0.35 * catchmentWeight + 0.25 * urgencyWeight);
    return double.parse(score.toStringAsFixed(1));
  }

  static FieldDrainMatch? _findNearestDrain(double latitude, double longitude) {
    FieldDrainMatch? nearest;
    var nearestDistance = double.infinity;
    for (final drain in _knownDrains) {
      final distance = Geolocator.distanceBetween(
        latitude,
        longitude,
        drain.latitude,
        drain.longitude,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = drain;
      }
    }
    return nearestDistance <= 50 ? nearest : null;
  }

  Future<List<FieldNearbyPlace>> _fetchNearbyPlaces({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(_placesUrl).replace(
      queryParameters: {
        'categories': _facilityCategories.keys.join(','),
        'filter':
            'circle:$longitude,$latitude,${fieldPriorityRadiusMeters.round()}',
        'bias': 'proximity:$longitude,$latitude',
        'limit': '100',
        'apiKey': _apiKey,
      },
    );

    final http.Response response;
    try {
      response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw Exception('Geoapify lookup timed out. Check connectivity.');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Geoapify returned HTTP ${response.statusCode}. Check its key and quota.',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const FormatException('Geoapify returned invalid JSON.');
    }
    if (decoded is! Map<String, dynamic> || decoded['features'] is! List) {
      throw const FormatException('Unexpected Geoapify Places response.');
    }

    final places = <FieldNearbyPlace>[];
    final seen = <String>{};
    for (final feature in decoded['features'] as List<dynamic>) {
      if (feature is! Map<String, dynamic>) continue;
      final properties = feature['properties'];
      final geometry = feature['geometry'];
      if (properties is! Map<String, dynamic> ||
          geometry is! Map<String, dynamic>) {
        continue;
      }
      final categories = properties['categories'];
      final coordinates = geometry['coordinates'];
      if (categories is! List ||
          coordinates is! List ||
          coordinates.length < 2 ||
          coordinates[0] is! num ||
          coordinates[1] is! num) {
        continue;
      }

      String? type;
      for (final category in categories.whereType<String>()) {
        type = _facilityCategories[category];
        if (type != null) break;
      }
      if (type == null) continue;

      final placeLongitude = (coordinates[0] as num).toDouble();
      final placeLatitude = (coordinates[1] as num).toDouble();
      if (placeLatitude < -90 ||
          placeLatitude > 90 ||
          placeLongitude < -180 ||
          placeLongitude > 180) {
        continue;
      }
      final distance = Geolocator.distanceBetween(
        latitude,
        longitude,
        placeLatitude,
        placeLongitude,
      );
      if (distance > fieldPriorityRadiusMeters) continue;

      final placeId = properties['place_id']?.toString();
      final key = placeId != null && placeId.isNotEmpty
          ? placeId
          : '${type}_${placeLatitude.toStringAsFixed(6)}_'
                '${placeLongitude.toStringAsFixed(6)}';
      if (!seen.add(key)) continue;
      final rawName = properties['name']?.toString().trim();
      places.add(
        FieldNearbyPlace(
          name: rawName == null || rawName.isEmpty ? 'Unnamed $type' : rawName,
          type: type,
          latitude: placeLatitude,
          longitude: placeLongitude,
          distanceMeters: distance,
        ),
      );
    }
    places.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return places;
  }
}
