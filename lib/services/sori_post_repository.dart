import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import '../config/app_config.dart';
import '../models/sori_post.dart';

/// 위치 기반 sori_posts 조회 + TTL 필터
class SoriPostRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GeoFlutterFire _geo = GeoFlutterFire();

  /// 반경 내 미만료 포스트 스트림 (GeoQuery)
  Stream<List<SoriPost>> watchNearby({
    required double latitude,
    required double longitude,
    double radiusKm = AppConfig.geoRadiusKm,
    String? languageFilter,
    String? tensionFilter,
  }) {
    final center = _geo.point(latitude: latitude, longitude: longitude);
    final radius = radiusKm <= 0 ? 10000.0 : radiusKm;

    return _geo
        .collection(collectionRef: _firestore.collection(AppConfig.soriPostsCollection))
        .within(
          center: center,
          radius: radius,
          field: 'position',
          strictMode: true,
        )
        .asyncMap((list) async {
      var posts = list
          .map((doc) => SoriPost.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>))
          .where((p) => !p.isExpired)
          .toList();

      if (languageFilter != null && languageFilter.isNotEmpty) {
        posts = posts.where((p) => p.language == languageFilter).toList();
      }
      if (tensionFilter != null && tensionFilter.isNotEmpty) {
        posts = posts.where((p) => p.tension == tensionFilter).toList();
      }
      return posts;
    });
  }

  /// 포스트 추가 시 position(geohash) 필드 포함해서 저장
  Future<String> addPost({
    required String audioUrl,
    required double latitude,
    required double longitude,
    required String language,
    required String tension,
    required double ttlHours,
    String mode = '거주자',
    String? ttlLabel,
    String? userName,
    int? durationSeconds,
  }) async {
    final now = DateTime.now();
    final hours = ttlHours.floor();
    final minutes = ((ttlHours - hours) * 60).round();
    final expiresAt = now.add(Duration(hours: hours, minutes: minutes));
    final geoPoint = GeoPoint(latitude, longitude);
    final position = _geo.point(latitude: latitude, longitude: longitude).data;

    final data = <String, dynamic>{
      'audio_url': audioUrl,
      'location': geoPoint,
      'position': position,
      'language': language,
      'tension': tension,
      'mode': mode,
      'ttl_label': ttlLabel,
      'user_name': userName,
      'created_at': Timestamp.fromDate(now),
      'expires_at': Timestamp.fromDate(expiresAt),
    };
    if (durationSeconds != null) data['duration_seconds'] = durationSeconds;
    final ref = await _firestore.collection(AppConfig.soriPostsCollection).add(data);
    return ref.id;
  }

  /// Storage 참조 (업로드용)
  Reference get storageRef =>
      FirebaseStorage.instance.ref().child(AppConfig.storageAudioPath);
}
