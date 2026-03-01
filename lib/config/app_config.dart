/// 앱 전역 설정
class AppConfig {
  /// 위치 기반 조회 반경 (km)
  static const double geoRadiusKm = 5.0;

  /// 데이터 부족 시 전국/인기 폴백 사용
  static const int minPostsForLocalOnly = 3;

  /// 새 음성 재생 전 시그널 사운드 길이 (초)
  static const double signalDurationSeconds = 0.5;

  /// 음성 TTL 기본값 (시간). 1~24 시간 범위 권장
  static const int defaultTtlHours = 12;

  /// Firestore 컬렉션명
  static const String soriPostsCollection = 'sori_posts';

  /// Storage 오디오 경로 prefix
  static const String storageAudioPath = 'sori_audio';
}
