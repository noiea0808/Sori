/// 들을 소리 목록/백그라운드 수신에 쓰는 사용자 설정
class ListenSettings {
  /// 반경 (km). 이 거리 안의 포스트만 조회
  final double radiusKm;

  /// 언어 필터. null이면 전체
  final String? languageFilter;

  /// tension 필터. null이면 전체
  final String? tensionFilter;

  /// 근처 포스트가 적을 때 전국/인기 폴백 사용 여부
  final bool fallbackToGlobal;

  /// 최초 실행 후 설정 완료 여부 (온보딩 완료 시 true)
  final bool hasCompletedOnboarding;

  const ListenSettings({
    this.radiusKm = 5.0,
    this.languageFilter,
    this.tensionFilter,
    this.fallbackToGlobal = true,
    this.hasCompletedOnboarding = false,
  });

  ListenSettings copyWith({
    double? radiusKm,
    String? languageFilter,
    String? tensionFilter,
    bool? fallbackToGlobal,
    bool? hasCompletedOnboarding,
  }) {
    return ListenSettings(
      radiusKm: radiusKm ?? this.radiusKm,
      languageFilter: languageFilter ?? this.languageFilter,
      tensionFilter: tensionFilter ?? this.tensionFilter,
      fallbackToGlobal: fallbackToGlobal ?? this.fallbackToGlobal,
      hasCompletedOnboarding: hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    );
  }

  Map<String, dynamic> toJson() => {
        'radiusKm': radiusKm,
        'languageFilter': languageFilter,
        'tensionFilter': tensionFilter,
        'fallbackToGlobal': fallbackToGlobal,
        'hasCompletedOnboarding': hasCompletedOnboarding,
      };

  static ListenSettings fromJson(Map<String, dynamic> json) {
    return ListenSettings(
      radiusKm: (json['radiusKm'] as num?)?.toDouble() ?? 5.0,
      languageFilter: json['languageFilter'] as String?,
      tensionFilter: json['tensionFilter'] as String?,
      fallbackToGlobal: json['fallbackToGlobal'] as bool? ?? true,
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
    );
  }
}
