import 'package:cloud_firestore/cloud_firestore.dart';

/// sori_posts 컬렉션 문서 모델
class SoriPost {
  final String id;
  final String audioUrl;
  final GeoPoint location;
  final String language;
  final String tension;
  final String mode;
  final String? ttlLabel;
  final String? userName;
  final int? durationSeconds;
  final DateTime createdAt;
  final DateTime expiresAt;

  const SoriPost({
    required this.id,
    required this.audioUrl,
    required this.location,
    required this.language,
    required this.tension,
    this.mode = '거주자',
    this.ttlLabel,
    this.userName,
    this.durationSeconds,
    required this.createdAt,
    required this.expiresAt,
  });

  String get languageLabel => _languageLabel(language);
  String get tensionLabel => _tensionLabel(tension);

  String get durationLabel {
    if (durationSeconds == null) return '';
    final d = Duration(seconds: durationSeconds!);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  static String _languageLabel(String v) {
    switch (v) {
      case 'ko': return '한국어';
      case 'en': return '영어';
      case 'ja': return '일본어';
      case 'zh': return '중국어';
      default: return '기타';
    }
  }

  static String _tensionLabel(String v) {
    switch (v) {
      case 'Calm': return '조용';
      case 'Focus': return '중간';
      case 'Energetic': return '활기찬';
      default: return v;
    }
  }

  factory SoriPost.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return SoriPost(
      id: doc.id,
      audioUrl: data['audio_url'] as String,
      location: data['location'] as GeoPoint,
      language: data['language'] as String? ?? 'unknown',
      tension: data['tension'] as String? ?? 'Calm',
      mode: data['mode'] as String? ?? '거주자',
      ttlLabel: data['ttl_label'] as String?,
      userName: data['user_name'] as String?,
      durationSeconds: () {
        final v = data['duration_seconds'];
        if (v == null) return null;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return null;
      }(),
      createdAt: (data['created_at'] as Timestamp).toDate(),
      expiresAt: (data['expires_at'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'audio_url': audioUrl,
      'location': location,
      'language': language,
      'tension': tension,
      'created_at': Timestamp.fromDate(createdAt),
      'expires_at': Timestamp.fromDate(expiresAt),
    };
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
