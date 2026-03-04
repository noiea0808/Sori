/// 들을 소리 목록/백그라운드 수신에 쓰는 사용자 설정
class ListenSettings {
  /// 모드: '거주자' | '여행자'
  final String mode;

  /// 반경 (km). <= 0 이면 무제한(10000)
  final double radiusKm;

  /// 언어 필터. null이면 전체
  final String? languageFilter;

  /// tension 필터. null이면 전체. Calm(조용) | Focus(중간) | Energetic(활기찬)
  final String? tensionFilter;

  /// 최초 실행 후 설정 완료 여부 (온보딩 완료 시 true)
  final bool hasCompletedOnboarding;

  const ListenSettings({
    this.mode = '거주자',
    this.radiusKm = 5.0,
    this.languageFilter,
    this.tensionFilter,
    this.hasCompletedOnboarding = false,
  });

  double get effectiveRadiusKm => radiusKm <= 0 ? 10000.0 : radiusKm;

  ListenSettings copyWith({
    String? mode,
    double? radiusKm,
    String? languageFilter,
    String? tensionFilter,
    bool? hasCompletedOnboarding,
  }) {
    return ListenSettings(
      mode: mode ?? this.mode,
      radiusKm: radiusKm ?? this.radiusKm,
      languageFilter: languageFilter ?? this.languageFilter,
      tensionFilter: tensionFilter ?? this.tensionFilter,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'radiusKm': radiusKm,
        'languageFilter': languageFilter,
        'tensionFilter': tensionFilter,
        'hasCompletedOnboarding': hasCompletedOnboarding,
      };

  static ListenSettings fromJson(Map<String, dynamic> json) {
    final r = (json['radiusKm'] as num?)?.toDouble();
    return ListenSettings(
      mode: json['mode'] as String? ?? '거주자',
      radiusKm: r ?? 5.0,
      languageFilter: json['languageFilter'] as String?,
      tensionFilter: json['tensionFilter'] as String?,
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
    );
  }
}

/// 반경 옵션 (100m ~ 무제한)
class RadiusOption {
  final String label;
  final double km; // 0 = 무제한

  const RadiusOption(this.label, this.km);
  static const values = [
    RadiusOption('100m', 0.1),
    RadiusOption('500m', 0.5),
    RadiusOption('1km', 1),
    RadiusOption('3km', 3),
    RadiusOption('5km', 5),
    RadiusOption('10km', 10),
    RadiusOption('50km', 50),
    RadiusOption('100km', 100),
    RadiusOption('무제한', 0),
  ];
}

/// 언어 옵션 (표시명, Firestore 값)
class LanguageOption {
  final String label;
  final String? value; // null = 전체

  const LanguageOption(this.label, this.value);
  static const values = [
    LanguageOption('전체', null),
    LanguageOption('한국어', 'ko'),
    LanguageOption('영어', 'en'),
    LanguageOption('일본어', 'ja'),
    LanguageOption('중국어', 'zh'),
    LanguageOption('기타', 'unknown'),
  ];
}

/// 텐션 옵션 (표시명, Firestore 값)
class TensionOption {
  final String label;
  final String? value; // null = 전체

  const TensionOption(this.label, this.value);
  static const values = [
    TensionOption('전체', null),
    TensionOption('조용', 'Calm'),
    TensionOption('중간', 'Focus'),
    TensionOption('활기찬', 'Energetic'),
  ];
}
