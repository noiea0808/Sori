import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/record_settings.dart';
import 'sori_post_repository.dart';

/// 즉시 녹음 후 Storage 업로드 + Firestore 등록
class RecordUploadService {
  final AudioRecorder _recorder = AudioRecorder();
  final SoriPostRepository _repo = SoriPostRepository();
  final _uuid = const Uuid();

  bool _isRecording = false;

  bool get isRecording => _isRecording;

  /// 롱프레스 동안 호출: 녹음 시작
  Future<bool> startRecording() async {
    if (_isRecording) return false;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/sori_${_uuid.v4()}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 22050,
        bitRate: 64000,
        numChannels: 1,
      ),
      path: path,
    );
    _isRecording = true;
    return true;
  }

  /// 녹음만 중지 (업로드 없음). 위치를 못 가져올 때 사용
  Future<void> stopRecordingWithoutUpload() async {
    if (!_isRecording) return;
    await _recorder.stop();
    _isRecording = false;
  }

  /// 롱프레스 해제 시 호출: 녹음 중지 → 업로드 → Firestore 등록
  Future<String?> stopRecordingAndUpload({
    required double latitude,
    required double longitude,
    required RecordSettings settings,
  }) async {
    if (!_isRecording) return null;
    final path = await _recorder.stop();
    _isRecording = false;
    if (path == null || path.isEmpty) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    final fileName = '${_uuid.v4()}.m4a';
    final ref = _repo.storageRef.child(fileName);

    await ref.putFile(
      file,
      SettableMetadata(contentType: 'audio/mp4'),
    );
    final audioUrl = await ref.getDownloadURL();

    int? durationSeconds;
    try {
      final player = AudioPlayer();
      await player.setFilePath(path);
      Duration? d;
      try {
        d = await player.durationStream
            .where((x) => x != null)
            .cast<Duration>()
            .first
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        d = player.duration;
      }
      if (d != null) durationSeconds = d.inSeconds;
      await player.dispose();
    } catch (_) {}

    final ttlOpt = TtlOption.values.firstWhere(
      (o) => (o.hours - settings.ttlHours).abs() < 0.01,
      orElse: () => TtlOption.values.first,
    );
    final id = await _repo.addPost(
      audioUrl: audioUrl,
      latitude: latitude,
      longitude: longitude,
      language: settings.language,
      tension: settings.tension,
      ttlHours: settings.ttlHours,
      mode: settings.mode,
      ttlLabel: ttlOpt.label,
      userName: settings.userName,
      durationSeconds: durationSeconds,
    );

    try {
      await file.delete();
    } catch (_) {}

    return id;
  }
}
