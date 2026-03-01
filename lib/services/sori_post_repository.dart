import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geoflutterfire2/geoflutterfire2.dart';
import '../config/app_config.dart';
import '../models/sori_post.dart';

/// 위치 기반 sori_posts 조회 + TTL 필터
class SoriPostRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GeoFlutterFire _geo = GeoFlutterFire();

  /// 반경 5km 내 미만료 포스트 스트림 (GeoQuery)
  /// 데이터 부족 시 [fallbackToGlobal] true면 전국/인기 폴백
  Stream<List<SoriPost>> watchNearby({
    required double latitude,
    required double longitude,
    double radiusKm = AppConfig.geoRadiusKm,
    bool fallbackToGlobal = true,
  }) {
    final center = _geo.point(latitude: latitude, longitude: longitude);
    final now = DateTime.now();

    return _geo
        .collection(collectionRef: _firestore.collection(AppConfig.soriPostsCollection))
        .within(
          center: center,
          radius: radiusKm,
          field: 'position',
          strictMode: true,
        )
        .asyncMap((list) async {
      final posts = list
          .map((doc) => SoriPost.fromFirestore(doc))
          .where((p) => !p.isExpired)
          .toList();

      if (fallbackToGlobal && posts.length < AppConfig.minPostsForLocalOnly) {
        final global = await _fetchGlobalFallback(now);
        return global.isEmpty ? posts : global;
      }
      return posts;
    });
  }

  /// 전국/인기 폴백: expires_at 미만료, created_at 최신순
  /// (Firestore 복합 인덱스: expires_at ASC, created_at DESC)
  Future<List<SoriPost>> _fetchGlobalFallback(DateTime now) async {
    final snap = await _firestore
        .collection(AppConfig.soriPostsCollection)
        .where('expires_at', isGreaterThan: Timestamp.fromDate(now))
        .orderBy('expires_at')
        .orderBy('created_at', descending: true)
        .limit(50)
        .get();

    return snap.docs.map((d) => SoriPost.fromFirestore(d)).toList();
  }

  /// 포스트 추가 시 position(geohash) 필드 포함해서 저장
  Future<String> addPost({
    required String audioUrl,
    required double latitude,
    required double longitude,
    required String language,
    String tension = 'Calm',
    int ttlHours = AppConfig.defaultTtlHours,
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(Duration(hours: ttlHours));
    final geoPoint = GeoPoint(latitude, longitude);
    final position = _geo.point(latitude: latitude, longitude: longitude).data;

    final ref = await _firestore.collection(AppConfig.soriPostsCollection).add({
      'audio_url': audioUrl,
      'location': geoPoint,
      'position': position,
      'language': language,
      'tension': tension,
      'created_at': Timestamp.fromDate(now),
      'expires_at': Timestamp.fromDate(expiresAt),
    });
    return ref.id;
  }

  /// Storage 참조 (업로드용)
  Reference get storageRef =>
      FirebaseStorage.instance.ref().child(AppConfig.storageAudioPath);
}
