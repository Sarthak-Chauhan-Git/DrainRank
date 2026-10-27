import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import 'detected_object.dart';

class BottleDetector {
  BottleDetector._();

  static final BottleDetector instance = BottleDetector._();

  static const _modelAsset = 'packages/ai_detector/1.tflite';
  static const _inputSize = 320;
  static const _scoreThreshold = 0.1;
  static const _labelMapAsset = 'packages/ai_detector/labelmap.txt';

  Future<Interpreter>? _interpreterFuture;
  Future<List<String>>? _labelsFuture;

  Future<bool> containsBottle(Uint8List imageBytes) async {
    return (await detectObjects(imageBytes)).bottleDetected;
  }

  Future<ObjectDetectionResult> detectObjects(Uint8List imageBytes) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) {
      throw const FormatException('The captured photo could not be decoded.');
    }

    final oriented = img.bakeOrientation(decoded);
    final labels = await (_labelsFuture ??= rootBundle
        .loadString(_labelMapAsset)
        .then(
          (contents) =>
              contents.split('\n').map((label) => label.trim()).toList(),
        ));
    final resized = img.copyResize(
      oriented,
      width: _inputSize,
      height: _inputSize,
    );
    final input = Uint8List(_inputSize * _inputSize * 3);
    var offset = 0;
    for (var y = 0; y < _inputSize; y++) {
      for (var x = 0; x < _inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        input[offset++] = pixel.r.toInt();
        input[offset++] = pixel.g.toInt();
        input[offset++] = pixel.b.toInt();
      }
    }

    final interpreter = await (_interpreterFuture ??= Interpreter.fromAsset(
      _modelAsset,
      options: InterpreterOptions()..threads = 2,
    ));
    final inputTensor = interpreter.getInputTensor(0);
    if (inputTensor.type != TensorType.uint8 ||
        inputTensor.shape.length != 4 ||
        inputTensor.shape[0] != 1 ||
        inputTensor.shape[1] != _inputSize ||
        inputTensor.shape[2] != _inputSize ||
        inputTensor.shape[3] != 3) {
      throw StateError('The bottle detector model has an unsupported input.');
    }
    inputTensor.data = input;
    interpreter.invoke();

    final outputs = interpreter.getOutputTensors();
    final boxes = outputs.firstWhere(
      (tensor) => tensor.shape.length == 3 && tensor.shape.last == 4,
      orElse: () => throw StateError(
        'The bottle detector model is missing its boxes output.',
      ),
    );
    final count = outputs.firstWhere(
      (tensor) => tensor.shape.length == 1 && tensor.shape[0] == 1,
      orElse: () => throw StateError(
        'The bottle detector model is missing its count output.',
      ),
    );
    if (boxes.type != TensorType.float32) {
      throw StateError('The bottle detector model has unsupported outputs.');
    }

    final classes = _readFloatValues(
      _findOutput(outputs, 'StatefulPartitionedCall:2'),
    );
    final scores = _readFloatValues(
      _findOutput(outputs, 'StatefulPartitionedCall:1'),
    );
    final detectionCount = _readFloatValues(count).single.round();
    final boxValues = _readFloatValues(boxes);
    final maxBoxes = boxes.shape[1];
    final maxDetections = [
      detectionCount,
      maxBoxes,
      scores.length,
      classes.length,
    ].reduce((a, b) => a < b ? a : b);

    final detections = <DetectedObject>[];
    for (var i = 0; i < maxDetections; i++) {
      final classId = classes[i].round();
      if (scores[i] < _scoreThreshold ||
          classId < 0 ||
          classId >= labels.length ||
          labels[classId] == '???') {
        continue;
      }
      final boxOffset = i * 4;
      final ymin = boxValues[boxOffset].clamp(0.0, 1.0);
      final xmin = boxValues[boxOffset + 1].clamp(0.0, 1.0);
      final ymax = boxValues[boxOffset + 2].clamp(0.0, 1.0);
      final xmax = boxValues[boxOffset + 3].clamp(0.0, 1.0);
      if (xmax <= xmin || ymax <= ymin) continue;

      detections.add(
        DetectedObject(
          label: labels[classId],
          confidence: scores[i],
          bounds: Rect.fromLTRB(xmin, ymin, xmax, ymax),
        ),
      );
    }

    return ObjectDetectionResult(
      imageWidth: oriented.width,
      imageHeight: oriented.height,
      detections: List.unmodifiable(detections),
    );
  }

  List<double> _readFloatValues(Tensor tensor) {
    if (tensor.type != TensorType.float32) {
      throw StateError('The bottle detector model has an unsupported output.');
    }
    final bytes = tensor.data;
    if (bytes.lengthInBytes % 4 != 0) {
      throw StateError('The bottle detector returned malformed output data.');
    }
    final data = ByteData.sublistView(bytes);
    return List<double>.generate(
      bytes.lengthInBytes ~/ 4,
      (index) => data.getFloat32(index * 4, Endian.little),
    );
  }

  Tensor _findOutput(List<Tensor> outputs, String name) {
    return outputs.firstWhere(
      (tensor) =>
          tensor.name == name &&
          tensor.shape.length == 2 &&
          tensor.shape[0] == 1 &&
          tensor.type == TensorType.float32,
      orElse: () => throw StateError(
        'The bottle detector model is missing the $name output.',
      ),
    );
  }
}
