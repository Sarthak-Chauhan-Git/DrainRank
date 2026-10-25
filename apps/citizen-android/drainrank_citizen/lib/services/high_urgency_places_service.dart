import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

enum FacilityPriority { high, elevated }

class NearbyUrgencyFacility {
  final String name;
  final String type;
  final double latitude;
  final double longitude;
  final FacilityPriority priority;
  final double distanceMeters;

  const NearbyUrgencyFacility({
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
    required this.priority,
    required this.distanceMeters,
  });
}

class HighUrgencyPlacesService {
  static const String _apiKey = String.fromEnvironment('GEOAPIFY_API_KEY');

  static const String _baseUrl = 'https://api.geoapify.com/v2/places';

  static const Duration _requestTimeout = Duration(seconds: 15);

  static const double defaultRadiusMeters = 500;

  static const Map<String, String> _categoryTypes = {
    'healthcare.hospital': 'hospital',
    'education.school': 'school',
    'education.university': 'university',
    'education.college': 'college',
    'service.police': 'police station',
    'service.fire_station': 'fire station',
  };

  static const Set<String> _highPriorityTypes = {
    'hospital',
    'police station',
    'fire station',
  };

  Future<List<NearbyUrgencyFacility>> fetchNearbyPlaces({
    required double latitude,
    required double longitude,
    double radiusMeters = defaultRadiusMeters,
  }) async {
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        radiusMeters <= 0 ||
        radiusMeters > 50000) {
      throw ArgumentError('Invalid coordinates or search radius.');
    }

    if (_apiKey.isEmpty) {
      throw StateError(
        'Geoapify API key is missing. '
        'Launch Flutter with '
        '--dart-define=GEOAPIFY_API_KEY=YOUR_KEY.',
      );
    }

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'categories': _categoryTypes.keys.join(','),
        'filter': 'circle:$longitude,$latitude,${radiusMeters.round()}',
        'bias': 'proximity:$longitude,$latitude',
        'limit': '100',
        'apiKey': _apiKey,
      },
    );

    final http.Response response;

    try {
      response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw Exception(
        'Geoapify request timed out. Check your internet '
        'connection and try again.',
      );
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Geoapify returned HTTP ${response.statusCode}. '
        'Check the API key, quota, and request configuration.',
      );
    }

    final dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw Exception('Geoapify returned invalid JSON.');
    }

    if (decoded is! Map<String, dynamic> || decoded['features'] is! List) {
      throw const FormatException('Unexpected Geoapify Places response.');
    }

    final features = decoded['features'] as List<dynamic>;
    final places = <NearbyUrgencyFacility>[];
    final seen = <String>{};

    for (final feature in features) {
      if (feature is! Map<String, dynamic>) continue;

      final properties = feature['properties'];
      if (properties is! Map<String, dynamic>) continue;

      final categories = properties['categories'];
      if (categories is! List) continue;

      String? matchedType;

      for (final category in categories) {
        if (category is! String) continue;

        matchedType = _categoryTypes[category];

        if (matchedType != null) break;
      }

      if (matchedType == null) continue;

      final geometry = feature['geometry'];
      if (geometry is! Map<String, dynamic>) continue;

      final coordinates = geometry['coordinates'];

      if (coordinates is! List || coordinates.length < 2) {
        continue;
      }

      // GeoJSON order is [longitude, latitude].
      final lon = coordinates[0];
      final lat = coordinates[1];

      if (lon is! num || lat is! num) continue;

      final placeLongitude = lon.toDouble();
      final placeLatitude = lat.toDouble();

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

      // Independently enforce the requested radius.
      if (distance > radiusMeters) continue;

      final rawName = properties['name']?.toString().trim();

      final name = rawName == null || rawName.isEmpty
          ? 'Unnamed $matchedType'
          : rawName;

      final placeId = properties['place_id']?.toString();

      final deduplicationKey = placeId != null && placeId.isNotEmpty
          ? placeId
          : '${matchedType}_'
                '${placeLatitude.toStringAsFixed(6)}_'
                '${placeLongitude.toStringAsFixed(6)}';

      if (!seen.add(deduplicationKey)) continue;

      final priority = _highPriorityTypes.contains(matchedType)
          ? FacilityPriority.high
          : FacilityPriority.elevated;

      places.add(
        NearbyUrgencyFacility(
          name: name,
          type: matchedType,
          latitude: placeLatitude,
          longitude: placeLongitude,
          priority: priority,
          distanceMeters: distance,
        ),
      );
    }

    // Nearest facilities appear first.
    places.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

    return places;
  }

  bool isWithinUrgencyRadius({
    required double reportLatitude,
    required double reportLongitude,
    required NearbyUrgencyFacility place,
    double radiusMeters = defaultRadiusMeters,
  }) {
    final distance = Geolocator.distanceBetween(
      reportLatitude,
      reportLongitude,
      place.latitude,
      place.longitude,
    );

    return distance <= radiusMeters;
  }
}
