import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

import 'overlay_main.dart';
import 'services/location_service.dart';
import 'services/record_upload_service.dart';
import 'services/sori_background_audio_handler.dart';
import 'services/sori_playback_queue_service.dart';
import 'package:audio_service/audio_service.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase 초기화 (FlutterFire CLI 사용 시 Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform) 추가)
  // await Firebase.initializeApp();

  await configureAudioSession();

  runApp(const SoriApp());
}

class SoriApp extends StatelessWidget {
  const SoriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '소리 Sori',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final LocationService _location = LocationService();
  final RecordUploadService _recordUpload = RecordUploadService();
  final SoriPlaybackQueueService _queueService = SoriPlaybackQueueService();

  bool _audioServiceReady = false;
  bool _isPlaying = false;
  String _status = '시작하기';

  @override
  void initState() {
    super.initState();
    _initAudioService();
  }

  Future<void> _initAudioService() async {
    _audioServiceReady = await AudioService.init(
      builder: () => SoriBackgroundAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.sori.sori.audio',
        androidNotificationChannelName: '소리 재생',
        androidStopForegroundOnPause: false,
      ),
    );
    if (!_audioServiceReady) {
      setState(() => _status = '오디오 서비스 초기화 실패');
      return;
    }
    final handler = AudioService.instance as SoriBackgroundAudioHandler;
    _queueService.setHandler(handler);

    handler.playbackState.listen((state) {
      if (state.processingState == AudioProcessingState.completed) {
        _queueService.onTrackCompleted();
      }
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });
  }

  Future<void> _startListening() async {
    final locationOk = await _location.requestPermission();
    if (!locationOk) {
      setState(() => _status = '위치 권한을 허용해 주세요');
      return;
    }
    await _queueService.start();
    setState(() => _status = '수신 중… (플로팅 버튼으로 제어)');
  }

  Future<void> _showOverlay() async {
    final status = await Permission.systemAlertWindow.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() => _status = '다른 앱 위에 표시 권한이 필요합니다');
      }
      return;
    }
    await FlutterOverlayWindow.showOverlay(
      height: 80,
      width: 80,
      alignment: OverlayAlignment.centerRight,
      visibility: NotificationVisibility.visibilityPublic,
      flag: OverlayFlag.defaultFlag,
      enableDrag: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('소리 Sori'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              if (!_audioServiceReady)
                const CircularProgressIndicator()
              else ...[
                FilledButton.icon(
                  onPressed: _startListening,
                  icon: const Icon(Icons.radio),
                  label: const Text('수신 시작'),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _showOverlay,
                  child: const Text('플로팅 버튼 켜기'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _queueService.stop();
    super.dispose();
  }
}

/// 플로팅 오버레이 전용 엔트리포인트 (flutter_overlay_window에서 호출)
@pragma("vm:entry-point")
void overlayMain() {
  runApp(const OverlayApp());
}
