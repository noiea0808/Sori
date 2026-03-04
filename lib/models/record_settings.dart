/// 녹음 시 사용하는 설정 (기기별 저장)
class RecordSettings {
  final String? userName; // 사용자명 (MVP: 소리 남기기 시 입력)
  final String mode; // 거주자 | 여행자
  final String language; // ko, en, ja, zh, unknown
  final String tension; // Calm, Focus, Energetic
  final double ttlHours; // 0.5(30분), 1, 3, 6, 12, 24, 168(일주일), 720(한달), 8760(무제한)

  const RecordSettings({
    this.userName,
    this.mode = '거주자',
    this.language = 'ko',
    this.tension = 'Calm',
    this.ttlHours = 12,
  });

  RecordSettings copyWith({
    String? userName,
    String? mode,
    String? language,
    String? tension,
    double? ttlHours,
  }) {
    return RecordSettings(
      userName: userName ?? this.userName,
      mode: mode ?? this.mode,
      language: language ?? this.language,
      tension: tension ?? this.tension,
      ttlHours: ttlHours ?? this.ttlHours,
    );
  }

  Map<String, dynamic> toJson() => {
        'userName': userName,
        'mode': mode,
        'language': language,
        'tension': tension,
        'ttlHours': ttlHours,
      };

  static RecordSettings fromJson(Map<String, dynamic> json) {
    return RecordSettings(
      userName: json['userName'] as String?,
      mode: json['mode'] as String? ?? '거주자',
      language: json['language'] as String? ?? 'ko',
      tension: json['tension'] as String? ?? 'Calm',
      ttlHours: (json['ttlHours'] as num?)?.toDouble() ?? 12,
    );
  }
}

/// 유지시간 옵션 (표시명, 시간)
class TtlOption {
  final String label;
  final double hours;

  const TtlOption(this.label, this.hours);
  static const values = [
    TtlOption('무제한', 8760),
    TtlOption('30분', 0.5),
    TtlOption('1시간', 1),
    TtlOption('3시간', 3),
    TtlOption('6시간', 6),
    TtlOption('12시간', 12),
    TtlOption('24시간', 24),
    TtlOption('일주일', 168),
    TtlOption('한달', 720),
  ];
}
