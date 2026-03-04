import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/record_settings.dart';

/// 녹음 설정 저장/로드 (기기별)
class RecordSettingsService {
  static const String _key = 'sori_record_settings';

  Future<RecordSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_key);
    if (json == null) return const RecordSettings();
    try {
      return RecordSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(json) as Map),
      );
    } catch (_) {
      return const RecordSettings();
    }
  }

  Future<void> save(RecordSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}
