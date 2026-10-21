import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class HighUrgencyPlace {
  final String name;
  final String type;
  final double latitude;
  final double longitude;

  const HighUrgencyPlace({
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
  });
}

class HighUrgencyPlacesService {
  static const List<String> _overpassUrls = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];

  static const Duration _endpointTimeout =
  Duration(seconds: 12);

  Future<List<HighUrgencyPlace>> fetchNearbyPlaces({
    required double latitude,
    required double longitude,
    double radiusMeters = 500,
  }) async {
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        radiusMeters <= 0) {
      throw ArgumentError('Invalid location or search radius.');
    }

    final query = '''
[out:json][timeout:10];
(
  nwr(around:${radiusMeters.toInt()},$latitude,$longitude)["amenity"="hospital"];
  nwr(around:${radiusMeters.toInt()},$latitude,$longitude)["amenity"="school"];
);
out center tags;
''';

    final errors = <String>[];

    for (final endpoint in _overpassUrls) {
      try {
        final response = await http
            .post(
          Uri.parse(endpoint),
          headers: const {
            'Content-Type':
            'application/x-www-form-urlencoded',
            'Accept': 'application/json',
          },
          body: {'data': query},
        )
            .timeout(_endpointTimeout);

        if (response.statusCode != 200) {
          errors.add(
            '${Uri.parse(endpoint).host}: HTTP ${response.statusCode}',
          );
          continue;
        }

        final decoded = jsonDecode(response.body);

        if (decoded is! Map<String, dynamic> ||
            decoded['elements'] is! List) {
          errors.add(
            '${Uri.parse(endpoint).host}: invalid response format',
          );
          continue;
        }

        final elements = decoded['elements'] as List<dynamic>;
        final places = <HighUrgencyPlace>[];
        final seen = <String>{};

        for (final item in elements) {
          if (item is! Map<String, dynamic>) continue;

          final tags = item['tags'];
          if (tags is! Map<String, dynamic>) continue;

          final amenity = tags['amenity'];
          if (amenity != 'hospital' && amenity != 'school') {
            continue;
          }

          final center = item['center'];
          final lat = item['lat'] ??
              (center is Map<String, dynamic>
                  ? center['lat']
                  : null);
          final lon = item['lon'] ??
              (center is Map<String, dynamic>
                  ? center['lon']
                  : null);

          if (lat is! num || lon is! num) continue;

          final placeLat = lat.toDouble();
          final placeLon = lon.toDouble();

          if (placeLat < -90 ||
              placeLat > 90 ||
              placeLon < -180 ||
              placeLon > 180) {
            continue;
          }

          final id = '${item['type']}:${item['id']}';
          if (!seen.add(id)) continue;

          places.add(
            HighUrgencyPlace(
              name: tags['name']?.toString() ??
                  'Unnamed $amenity',
              type: amenity.toString(),
              latitude: placeLat,
              longitude: placeLon,
            ),
          );
        }

        // An empty list is a successful lookup with no matching
        // facilities returned by this query.
        return places;
      } on TimeoutException {
        errors.add(
          '${Uri.parse(endpoint).host}: request timed out',
        );
      } on FormatException {
        errors.add(
          '${Uri.parse(endpoint).host}: invalid JSON response',
        );
      } catch (e) {
        errors.add(
          '${Uri.parse(endpoint).host}: ${e.runtimeType}',
        );
      }
    }

    throw Exception(
      'Could not verify nearby facilities. '
          'All lookup endpoints failed. ${errors.join(' | ')}',
    );
  }

  bool isWithinUrgencyRadius({
    required double reportLatitude,
    required double reportLongitude,
    required HighUrgencyPlace place,
    double radiusMeters = 500,
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