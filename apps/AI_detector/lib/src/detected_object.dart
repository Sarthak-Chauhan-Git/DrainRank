import 'dart:ui' show Rect;

class DetectedObject {
  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.bounds,
  });

  final String label;
  final double confidence;
  final Rect bounds;
}

class ObjectDetectionResult {
  const ObjectDetectionResult({
    required this.imageWidth,
    required this.imageHeight,
    required this.detections,
  });

  final int imageWidth;
  final int imageHeight;
  final List<DetectedObject> detections;

  bool get bottleDetected =>
      detections.any((detection) => detection.label == 'bottle');
}
