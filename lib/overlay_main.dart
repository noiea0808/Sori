import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'services/location_service.dart';
import 'services/record_settings_service.dart';
import 'services/record_upload_service.dart';
import 'services/sori_background_audio_handler.dart';

/// 위치 조회 실패 시 사용하는 기본 좌표 (한국 중심)
const double _defaultLat = 36.5;
const double _defaultLng = 127.5;

/// 오버레이 UI (main.dart의 overlayMain에서 사용)
class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: OverlayPage(),
    );
  }
}

class OverlayPage extends StatefulWidget {
  @override
  State<OverlayPage> createState() => _OverlayPageState();
}

class _OverlayPageState extends State<OverlayPage> {
  final RecordUploadService _recordUpload = RecordUploadService();
  final LocationService _location = LocationService();
  final RecordSettingsService _recordSettingsService = RecordSettingsService();

  bool _isPlaying = false;
  bool _isRecording = false;
  /// 녹음 시작 시 미리 가져온 위치 (롱프레스 해제 시 사용)
  Position? _cachedPosition;

  @override
  void initState() {
    super.initState();
    _listenPlaybackState();
  }

  void _listenPlaybackState() {
    try {
      final handler = SoriBackgroundAudioHandler.instance;
      if (handler != null) {
        handler.playbackState.listen((state) {
          if (mounted) {
            setState(() => _isPlaying = state.playing);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _togglePlayPause() async {
    final handler = SoriBackgroundAudioHandler.instance;
    if (handler == null) return;
    if (_isPlaying) {
      await handler.pause();
    } else {
      await handler.play();
    }
  }

  Future<void> _onLongPressStart() async {
    setState(() => _isRecording = true);
    _cachedPosition = null;
    // 녹음하는 동안 위치를 미리 가져와 두어, 해제 시 바로 쓸 수 있게 함
    _location.getCurrentPosition().then((p) {
      if (mounted && _recordUpload.isRecording) _cachedPosition = p;
    });
    await _recordUpload.startRecording();
  }

  Future<void> _onLongPressEnd() async {
    if (!_recordUpload.isRecording) return;
    // 캐시된 위치가 있으면 사용, 없으면 한 번 더 시도
    Position? pos = _cachedPosition ?? await _location.getCurrentPosition();
    final usedDefaultLocation = pos == null;
    if (pos == null) {
      pos = Position(
        latitude: _defaultLat,
        longitude: _defaultLng,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
    }
    setState(() => _isRecording = false);
    _cachedPosition = null;
    try {
      final settings = await _recordSettingsService.load();
      final id = await _recordUpload.stopRecordingAndUpload(
        latitude: pos.latitude,
        longitude: pos.longitude,
        settings: settings,
      );
      if (mounted && id != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              usedDefaultLocation
                  ? '업로드 완료 (위치를 못 가져와 기본 위치로 등록했어요)'
                  : '업로드 완료',
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('녹음 파일이 없어 업로드하지 못했어요')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('업로드 실패: ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isRecording ? null : _togglePlayPause,
      onLongPressStart: (_) => _onLongPressStart(),
      onLongPressEnd: (_) => _onLongPressEnd(),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isRecording ? Colors.red : Colors.deepPurple,
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(
          _isRecording ? Icons.mic : (_isPlaying ? Icons.pause : Icons.play_arrow),
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }
}
