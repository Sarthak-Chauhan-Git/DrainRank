part of '../main.dart';

class LiveCameraCapture {
  const LiveCameraCapture({required this.image, required this.capturedAt});
  final XFile image;
  final DateTime capturedAt;
}

/// In-app camera preview on Android and supported browsers.
/// Never offers a gallery/file-picker fallback for work evidence.
class LiveWorkCameraPage extends StatefulWidget {
  const LiveWorkCameraPage({super.key});

  @override
  State<LiveWorkCameraPage> createState() => _LiveWorkCameraPageState();
}

class _LiveWorkCameraPageState extends State<LiveWorkCameraPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _capturing = false;
  String? _error;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera available on this device or browser.');
      }
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) return;
      setState(() => _initializing = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Camera unavailable: $e';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Avoid leaving the camera active when the app goes into the background.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _controller?.dispose();
      _controller = null;
      if (mounted) setState(() => _initializing = true);
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initializeCamera();
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (_capturing || controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final image = await controller.takePicture();
      final capturedAt = DateTime.now();
      if (!mounted) return;
      Navigator.of(context)
          .pop(LiveCameraCapture(image: image, capturedAt: capturedAt));
    } catch (e) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = 'Photo capture failed: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Live Work Camera')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center),
                      )
                    : _initializing ||
                          controller == null ||
                          !controller.value.isInitialized
                    ? const CircularProgressIndicator()
                    : CameraPreview(controller),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Take a new work photo. GPS coordinates and capture time are embedded in the JPG EXIF metadata.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: FilledButton.icon(
                onPressed: _error != null || _initializing || _capturing
                    ? null
                    : _capture,
                icon: const Icon(Icons.camera_alt),
                label: Text(_capturing ? 'Capturing...' : 'Capture photo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
