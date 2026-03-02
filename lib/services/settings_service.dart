import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/listen_settings.dart';

/// 설정 저장/로드 (SharedPreferences)
class SettingsService {
  static const String _keySettings = 'sori_listen_settings';

  Future<ListenSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_keySettings);
    if (json == null) return const ListenSettings();
    try {
      return ListenSettings.fromJson(
        Map<String, dynamic>.from(jsonDecode(json) as Map),
      );
    } catch (_) {
      return const ListenSettings();
    }
  }

  Future<void> save(ListenSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySettings, jsonEncode(settings.toJson()));
  }
}
