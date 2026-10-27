import 'package:flutter/material.dart';

import 'detected_object.dart';

class DetectedObjectImage extends StatelessWidget {
  const DetectedObjectImage({
    super.key,
    required this.image,
    required this.result,
    this.height,
    this.fit = BoxFit.cover,
  });

  final ImageProvider image;
  final ObjectDetectionResult? result;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final detectionResult = result;
    final imageWithDetections = Stack(
      fit: StackFit.expand,
      children: [
        Image(image: image, fit: fit),
        if (detectionResult != null && detectionResult.detections.isNotEmpty)
          CustomPaint(
            painter: _DetectionBoxPainter(result: detectionResult, fit: fit),
          ),
      ],
    );
    if (height == null) return imageWithDetections;
    return SizedBox(
      width: double.infinity,
      height: height,
      child: imageWithDetections,
    );
  }
}

class _DetectionBoxPainter extends CustomPainter {
  const _DetectionBoxPainter({required this.result, required this.fit});

  final ObjectDetectionResult result;
  final BoxFit fit;

  @override
  void paint(Canvas canvas, Size size) {
    final sourceSize = Size(
      result.imageWidth.toDouble(),
      result.imageHeight.toDouble(),
    );
    final fitted = applyBoxFit(fit, sourceSize, size);
    final sourceRect = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & sourceSize,
    );
    final destinationRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    final scaleX = destinationRect.width / sourceRect.width;
    final scaleY = destinationRect.height / sourceRect.height;

    for (final detection in result.detections) {
      final rect = Rect.fromLTRB(
        destinationRect.left +
            (detection.bounds.left * sourceSize.width - sourceRect.left) *
                scaleX,
        destinationRect.top +
            (detection.bounds.top * sourceSize.height - sourceRect.top) *
                scaleY,
        destinationRect.left +
            (detection.bounds.right * sourceSize.width - sourceRect.left) *
                scaleX,
        destinationRect.top +
            (detection.bounds.bottom * sourceSize.height - sourceRect.top) *
                scaleY,
      );
      final color = detection.label == 'bottle'
          ? const Color(0xFF00E676)
          : const Color(0xFF00B8D4);
      final border = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawRect(rect, border);

      final label =
          '${detection.label} '
          '${(detection.confidence * 100).round()}%';
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: (size.width - 10).clamp(1.0, size.width));
      final labelWidth = (text.width + 10).clamp(0.0, size.width);
      final labelHeight = text.height + 6;
      final labelRect = Rect.fromLTWH(
        rect.left.clamp(0.0, size.width - labelWidth),
        (rect.top - labelHeight).clamp(0.0, size.height - labelHeight),
        labelWidth,
        labelHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(3)),
        Paint()..color = color,
      );
      text.paint(canvas, Offset(labelRect.left + 5, labelRect.top + 3));
    }
  }

  @override
  bool shouldRepaint(_DetectionBoxPainter oldDelegate) {
    return oldDelegate.result != result || oldDelegate.fit != fit;
  }
}
