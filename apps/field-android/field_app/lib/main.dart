import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:typed_data';
import 'dart:math' as math;

import 'backend/supabase_backend.dart';
import 'services/priority_analysis.dart';

part 'app/app.dart';
part 'camera/gps_exif.dart';
part 'auth/auth.dart';
part 'admin/admin.dart';
part 'auth/access.dart';
part 'shared/date_helpers.dart';
part 'crew/credits.dart';
part 'crew/home.dart';
part 'crew/activity.dart';
part 'crew/direct_cleaning_report.dart';
part 'crew/debug_tool.dart';
part 'tasks/task_widgets.dart';
part 'tasks/task_helpers.dart';
part 'crew/leave.dart';
part 'tasks/task_details.dart';
part 'camera/live_camera.dart';
part 'tasks/task_detail_row.dart';

const _debugToolPin = '12345678';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
    runApp(const _FieldBackendSetupRequiredApp());
    return;
  }
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  runApp(const MunicipalCrewApp());
}

class _FieldBackendSetupRequiredApp extends StatelessWidget {
  const _FieldBackendSetupRequiredApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Supabase is not configured. Run this app with '
            '--dart-define=SUPABASE_URL=... and '
            '--dart-define=SUPABASE_PUBLISHABLE_KEY=... .',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
