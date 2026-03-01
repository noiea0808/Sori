import 'package:cloud_firestore/cloud_firestore.dart';

/// sori_posts 컬렉션 문서 모델
class SoriPost {
  final String id;
  final String audioUrl;
  final GeoPoint location;
  final String language;
  final String tension;
  final DateTime createdAt;
  final DateTime expiresAt;

  const SoriPost({
    required this.id,
    required this.audioUrl,
    required this.location,
    required this.language,
    required this.tension,
    required this.createdAt,
    required this.expiresAt,
  });

  factory SoriPost.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return SoriPost(
      id: doc.id,
      audioUrl: data['audio_url'] as String,
      location: data['location'] as GeoPoint,
      language: data['language'] as String? ?? 'unknown',
      tension: data['tension'] as String? ?? 'Calm',
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
