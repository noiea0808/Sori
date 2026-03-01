import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'services/location_service.dart';
import 'services/record_upload_service.dart';
import 'services/sori_background_audio_handler.dart';
import 'package:audio_service/audio_service.dart';

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

  bool _isPlaying = false;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _listenPlaybackState();
  }

  void _listenPlaybackState() {
    try {
      final handler = AudioService.instance;
      if (handler is SoriBackgroundAudioHandler) {
        handler.playbackState.listen((state) {
          if (mounted) {
            setState(() => _isPlaying = state.playing);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _togglePlayPause() async {
    final handler = AudioService.instance;
    if (handler is! SoriBackgroundAudioHandler) return;
    if (_isPlaying) {
      await handler.pause();
    } else {
      await handler.play();
    }
  }

  Future<void> _onLongPressStart() async {
    setState(() => _isRecording = true);
    await _recordUpload.startRecording();
  }

  Future<void> _onLongPressEnd() async {
    if (!_recordUpload.isRecording) return;
    final pos = await _location.getCurrentPosition();
    if (pos != null) {
      await _recordUpload.stopRecordingAndUpload(
        latitude: pos.latitude,
        longitude: pos.longitude,
        language: 'ko',
      );
    }
    setState(() => _isRecording = false);
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
