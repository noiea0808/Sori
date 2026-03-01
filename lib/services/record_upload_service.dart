import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
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

    final started = await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
        numChannels: 1,
      ),
      path: path,
    );
    _isRecording = started;
    return started;
  }

  /// 롱프레스 해제 시 호출: 녹음 중지 → 업로드 → Firestore 등록
  /// [latitude], [longitude], [language] 필요
  Future<String?> stopRecordingAndUpload({
    required double latitude,
    required double longitude,
    required String language,
    String tension = 'Calm',
    int ttlHours = AppConfig.defaultTtlHours,
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

    final id = await _repo.addPost(
      audioUrl: audioUrl,
      latitude: latitude,
      longitude: longitude,
      language: language,
      tension: tension,
      ttlHours: ttlHours,
    );

    try {
      await file.delete();
    } catch (_) {}

    return id;
  }
}
