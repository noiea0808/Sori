import 'package:flutter/material.dart';

import '../models/listen_settings.dart';

/// 들을 소리 설정: 모드, 반경, 언어, 텐션
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
  late String _mode;
  late double _radiusKm;
  late String? _languageFilter;
  late String? _tensionFilter;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialSettings.mode;
    _radiusKm = widget.initialSettings.radiusKm;
    _languageFilter = widget.initialSettings.languageFilter;
    _tensionFilter = widget.initialSettings.tensionFilter;
  }

  Future<void> _save() async {
    final settings = ListenSettings(
      mode: _mode,
      radiusKm: _radiusKm,
      languageFilter: _languageFilter,
      tensionFilter: _tensionFilter,
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
          Text('모드', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '거주자', label: Text('거주자')),
                    ButtonSegment(value: '여행자', label: Text('여행자')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() => _mode = v.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('반경', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: RadiusOption.values.map((opt) {
              final isSelected = (_radiusKm <= 0 && opt.km <= 0) ||
                  (_radiusKm > 0 && (opt.km - _radiusKm).abs() < 0.01);
              return FilterChip(
                label: Text(opt.label),
                selected: isSelected,
                onSelected: (_) => setState(() => _radiusKm = opt.km),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text('언어 필터', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: LanguageOption.values.map((opt) {
              final isSelected = _languageFilter == opt.value;
              return FilterChip(
                label: Text(opt.label),
                selected: isSelected,
                onSelected: (_) => setState(() => _languageFilter = opt.value),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Text('텐션 필터', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: TensionOption.values.map((opt) {
              final isSelected = _tensionFilter == opt.value;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FilterChip(
                    label: Text(opt.label, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _tensionFilter = opt.value),
                  ),
                ),
              );
            }).toList(),
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
