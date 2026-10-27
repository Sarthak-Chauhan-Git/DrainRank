import 'dart:typed_data';

import 'detected_object.dart';

class BottleDetector {
  BottleDetector._();

  static final BottleDetector instance = BottleDetector._();

  Future<bool> containsBottle(Uint8List imageBytes) {
    return Future<bool>.error(
      UnsupportedError('On-device bottle detection is unavailable on web.'),
    );
  }

  Future<ObjectDetectionResult> detectObjects(Uint8List imageBytes) {
    return Future<ObjectDetectionResult>.error(
      UnsupportedError('On-device object detection is unavailable on web.'),
    );
  }
}
