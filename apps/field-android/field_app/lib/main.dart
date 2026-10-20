import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:typed_data';
import 'dart:math' as math;

import 'firebase_options.dart';

part 'app/app.dart';
part 'camera/gps_exif.dart';
part 'auth/auth.dart';
part 'admin/admin.dart';
part 'auth/access.dart';
part 'shared/date_helpers.dart';
part 'crew/credits.dart';
part 'crew/home.dart';
part 'crew/activity.dart';
part 'tasks/task_widgets.dart';
part 'tasks/task_helpers.dart';
part 'crew/leave.dart';
part 'tasks/task_details.dart';
part 'camera/live_camera.dart';
part 'tasks/task_detail_row.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MunicipalCrewApp());
}
