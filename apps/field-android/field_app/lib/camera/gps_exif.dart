part of '../main.dart';

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
