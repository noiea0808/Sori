import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:geolocator/geolocator.dart';

import '../models/listen_settings.dart';
import '../models/sori_post.dart';
import 'location_service.dart';
import 'sori_background_audio_handler.dart';
import 'sori_post_repository.dart';

/// 위치 기반 포스트 큐를 관리하고, 백그라운드 핸들러로 순차 재생
class SoriPlaybackQueueService {
  final LocationService _location = LocationService();
  final SoriPostRepository _repo = SoriPostRepository();
  StreamSubscription<List<SoriPost>>? _postsSub;
  StreamSubscription<Position>? _positionSub;

  List<SoriPost> _currentPosts = [];
  int _currentIndex = 0;
  /// true면 playList()로 재생 중 → 전부 재생 후 정지
  bool _playListMode = false;
  Position? _lastPosition;
  SoriBackgroundAudioHandler? _handler;

  bool _isRunning = false;

  bool get isRunning => _isRunning;

  /// 오디오 핸들러 등록 (AudioService.init 후 호출)
  void setHandler(SoriBackgroundAudioHandler handler) {
    _handler = handler;
  }

  SoriBackgroundAudioHandler? get handler => _handler;

  /// 수신 시작: 위치 스트림 + GeoQuery로 근처 포스트 구독 → 재생 큐 갱신 → 완료 시 다음 트랙
  /// [settings]가 있으면 반경/폴백/필터 적용. 없으면 기본값 사용.
  Future<void> start([ListenSettings? settings]) async {
    if (_isRunning) return;
    _isRunning = true;
    _playListMode = false;
    _currentSettings = settings ?? const ListenSettings();

    final pos = await _location.getCurrentPosition();
    if (pos != null) {
      _lastPosition = pos;
      _subscribePosts(pos.latitude, pos.longitude);
    }

    _positionSub = _location.positionStream.listen((position) {
      _lastPosition = position;
      _subscribePosts(position.latitude, position.longitude);
    });
  }

  ListenSettings _currentSettings = const ListenSettings();

  void _subscribePosts(double lat, double lng) {
    _postsSub?.cancel();
    _postsSub = _repo
        .watchNearby(
          latitude: lat,
          longitude: lng,
          radiusKm: _currentSettings.effectiveRadiusKm,
          modeFilter: _currentSettings.mode != '전체' ? _currentSettings.mode : null,
          languageFilter: _currentSettings.languageFilter,
          tensionFilter: _currentSettings.tensionFilter,
          durationFilterSeconds: _currentSettings.durationFilterSeconds,
        )
        .listen((posts) {
      if (posts.isEmpty) return;
      _currentPosts = posts;
      _currentIndex = 0;
      _playNext();
    });
  }

  void _playNext() {
    if (_handler == null || _currentPosts.isEmpty) return;
    if (_currentIndex >= _currentPosts.length) {
      if (_playListMode) {
        stop();
        return;
      }
      _currentIndex = 0;
      if (_currentPosts.isEmpty) return;
    }
    final post = _currentPosts[_currentIndex];
    if (post.isExpired) {
      _currentIndex++;
      _playNext();
      return;
    }
    _handler!.playUrl(post.audioUrl);
    _currentIndex++;
  }

  /// 재생 완료 시 호출 (핸들러에서 completed 이벤트로 연결)
  void onTrackCompleted() {
    _playNext();
  }

  /// 목록에서 하나만 재생할 때 호출 (백그라운드 수신과 무관)
  void playSingleUrl(String url) {
    _handler?.playUrl(url);
  }

  void pause() {
    _handler?.pause();
  }

  void play() {
    _handler?.play();
  }

  /// 현재 재생 중인 트랙만 중지 (수신 큐는 유지)
  void stopCurrent() {
    _handler?.stop();
  }

  /// 필터링된 목록을 오래된 순서부터 전부 재생 (위치 구독 없이 한 번에 재생)
  void playList(List<SoriPost> posts) {
    stop();
    if (posts.isEmpty || _handler == null) return;
    _currentPosts = List.from(posts);
    _currentIndex = 0;
    _isRunning = true;
    _playListMode = true;
    _playNext();
  }

  void stop() {
    _isRunning = false;
    _playListMode = false;
    _postsSub?.cancel();
    _positionSub?.cancel();
    _postsSub = null;
    _positionSub = null;
    _currentPosts = [];
    _currentIndex = 0;
    _handler?.stop();
  }
}
