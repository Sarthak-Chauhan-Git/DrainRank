import 'package:flutter/material.dart';

class BottleDetectionNotice extends StatelessWidget {
  const BottleDetectionNotice({
    super.key,
    required this.bottleDetected,
    this.error,
  });

  final bool? bottleDetected;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error == null && bottleDetected == null) {
      return const SizedBox.shrink();
    }

    final Color color;
    final Color background;
    final IconData icon;
    final String message;

    if (error != null) {
      color = Colors.red.shade800;
      background = Colors.red.shade50;
      icon = Icons.error_outline;
      message = 'Bottle detection could not be completed: $error';
    } else if (bottleDetected == false) {
      color = Colors.deepOrange.shade800;
      background = Colors.orange.shade50;
      icon = Icons.warning_amber_rounded;
      message = 'Warning: No bottle identified in this photo.';
    } else {
      color = Colors.green.shade800;
      background = Colors.green.shade50;
      icon = Icons.check_circle_outline;
      message = 'Bottle identified in this photo.';
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
