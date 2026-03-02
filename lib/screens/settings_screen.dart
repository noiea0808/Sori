import 'package:flutter/material.dart';

import '../models/listen_settings.dart';

/// 반경, 언어, tension, 전국 폴백 설정
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initialSettings,
    required this.onSave,
  });

  final ListenSettings initialSettings;
  final Future<void> Function(ListenSettings) onSave;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _radiusKm;
  late String? _languageFilter;
  late String? _tensionFilter;
  late bool _fallbackToGlobal;

  static const List<String> languageOptions = ['전체', 'ko', 'en', 'ja', 'unknown'];
  static const List<String> tensionOptions = ['전체', 'Calm', 'Energetic', 'Focus', 'Sleep'];

  @override
  void initState() {
    super.initState();
    _radiusKm = widget.initialSettings.radiusKm;
    _languageFilter = widget.initialSettings.languageFilter;
    _tensionFilter = widget.initialSettings.tensionFilter;
    _fallbackToGlobal = widget.initialSettings.fallbackToGlobal;
  }

  Future<void> _save() async {
    final settings = ListenSettings(
      radiusKm: _radiusKm,
      languageFilter: _languageFilter,
      tensionFilter: _tensionFilter,
      fallbackToGlobal: _fallbackToGlobal,
      hasCompletedOnboarding: true,
    );
    await widget.onSave(settings);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('들을 소리 설정'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('저장'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          Text('반경 (km)', style: Theme.of(context).textTheme.titleSmall),
          Slider(
            value: _radiusKm,
            min: 1,
            max: 50,
            divisions: 49,
            label: '${_radiusKm.round()} km',
            onChanged: (v) => setState(() => _radiusKm = v),
          ),
          Text('${_radiusKm.round()} km', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 24),
          Text('언어 필터', style: Theme.of(context).textTheme.titleSmall),
          DropdownButtonFormField<String?>(
            value: _languageFilter,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('전체')),
              ...languageOptions.where((s) => s != '전체').map((s) => DropdownMenuItem(value: s, child: Text(s))),
            ],
            onChanged: (v) => setState(() => _languageFilter = v),
          ),
          const SizedBox(height: 16),
          Text('Tension 필터', style: Theme.of(context).textTheme.titleSmall),
          DropdownButtonFormField<String?>(
            value: _tensionFilter,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('전체')),
              ...tensionOptions.where((s) => s != '전체').map((s) => DropdownMenuItem(value: s, child: Text(s))),
            ],
            onChanged: (v) => setState(() => _tensionFilter = v),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('전국 폴백'),
            subtitle: const Text('근처 소리가 적을 때 전국/인기 목록 보기'),
            value: _fallbackToGlobal,
            onChanged: (v) => setState(() => _fallbackToGlobal = v),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _save,
            child: const Text('저장하고 목록 보기'),
          ),
        ],
      ),
    );
  }
}
