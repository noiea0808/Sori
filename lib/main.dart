import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'overlay_main.dart';
import 'models/listen_settings.dart';
import 'services/location_service.dart';
import 'services/record_settings_service.dart';
import 'services/record_upload_service.dart';
import 'services/settings_service.dart';
import 'services/sori_background_audio_handler.dart';
import 'services/sori_playback_queue_service.dart';
import 'services/sori_post_repository.dart';
import 'package:audio_service/audio_service.dart';
import 'package:geolocator/geolocator.dart';

import 'models/record_settings.dart';
import 'models/sori_post.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await configureAudioSession();

  runApp(const SoriApp());
}

class SoriApp extends StatefulWidget {
  const SoriApp({super.key});

  @override
  State<SoriApp> createState() => _SoriAppState();
}

class _SoriAppState extends State<SoriApp> {
  final SettingsService _settingsService = SettingsService();
  ListenSettings? _settings;
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await _settingsService.load();
    if (mounted) setState(() {
      _settings = s;
      _settingsLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '소리 Sori',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: !_settingsLoaded
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : HomePage(
              initialSettings: _settings!,
              onSave: (s) async {
                await _settingsService.save(s);
                if (mounted) setState(() => _settings = s);
              },
            ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.initialSettings,
    this.onSave,
  });

  final ListenSettings initialSettings;
  final Future<void> Function(ListenSettings)? onSave;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final LocationService _location = LocationService();
  final RecordUploadService _recordUpload = RecordUploadService();
  final SoriPlaybackQueueService _queueService = SoriPlaybackQueueService();
  final SoriPostRepository _repo = SoriPostRepository();
  final SettingsService _settingsService = SettingsService();

  ListenSettings _settings = const ListenSettings();
  bool _audioServiceReady = false;
  bool _isPlaying = false;
  /// 목록에서 지금 재생 중인 오디오 URL (일치하는 항목만 일시정지 표시)
  String? _currentPlayingUrl;
  bool _isLoadingPlay = false;
  Duration _currentPosition = Duration.zero;
  Duration? _currentDuration;
  String _status = '수신 대기';
  Future<Position?>? _positionFuture;
  Timer? _positionUpdateTimer;
  int _listRefreshKey = 0;

  Future<void> _refreshList() async {
    setState(() => _listRefreshKey++);
  }

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _positionFuture = _location.getCurrentPosition();
    _initAudioService();
    if (!_settings.hasCompletedOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _completeOnboarding());
    }
  }

  void _retryLocation() {
    setState(() {
      _positionFuture = _location.getCurrentPosition();
    });
  }

  Future<void> _refreshSettings() async {
    final s = await _settingsService.load();
    if (mounted) setState(() => _settings = s);
  }

  Future<void> _saveSettings(ListenSettings s) async {
    await _settingsService.save(s);
    if (mounted) setState(() => _settings = s);
    await widget.onSave?.call(s);
  }

  Future<void> _completeOnboarding() async {
    await _saveSettings(_settings.copyWith(hasCompletedOnboarding: true));
  }

  Future<void> _initAudioService() async {
    try {
      final handler = await AudioService.init<SoriBackgroundAudioHandler>(
        builder: () => SoriBackgroundAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.sori.sori.audio',
          androidNotificationChannelName: '소리 재생',
          androidStopForegroundOnPause: false,
        ),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('오디오 서비스 초기화 시간 초과'),
      );

      if (!mounted) return;
      _queueService.setHandler(handler);

      handler.mediaItem.listen((item) {
        if (mounted && item != null) {
          setState(() {
            if (item.duration != null) _currentDuration = item.duration;
            if (item.id.isNotEmpty) _currentPlayingUrl = item.id;
          });
        }
      });

      handler.playbackState.listen((state) {
        if (state.processingState == AudioProcessingState.completed) {
          _queueService.onTrackCompleted();
        }
        if (mounted) {
          _positionUpdateTimer?.cancel();
          if (state.playing || _currentPlayingUrl != null) {
            _positionUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
              if (!mounted) return;
              final h = _queueService.handler;
              if (h != null) setState(() {
                _currentPosition = h.currentPosition;
                _currentDuration = h.currentDuration;
              });
            });
          } else {
            _positionUpdateTimer = null;
          }
          setState(() {
            _isPlaying = state.playing;
            if (state.playing) _isLoadingPlay = false;
            _currentPosition = state.updatePosition;
            _currentDuration = _queueService.handler?.currentDuration;
            if (state.processingState == AudioProcessingState.completed) {
              _currentPlayingUrl = null;
              _isLoadingPlay = false;
              _currentPosition = Duration.zero;
              _currentDuration = null;
            }
          });
        }
      });

      _audioServiceReady = true;
      if (mounted) setState(() {});
    } on TimeoutException {
      if (mounted) setState(() {
        _status = '오디오 서비스 초기화 시간 초과. 앱을 다시 실행해 보세요.';
      });
    } catch (e) {
      if (mounted) setState(() {
        _status = '오디오 서비스 초기화 실패: $e';
      });
    }
  }

  Future<void> _startListening() async {
    final locationOk = await _location.requestPermission();
    if (!locationOk) {
      setState(() => _status = '위치 권한을 허용해 주세요');
      return;
    }
    await _queueService.start(_settings);
    setState(() => _status = '수신 중… (플로팅 버튼으로 제어)');
  }

  Future<void> _openRecordSheet() async {
    final pos = await _location.getCurrentPosition();
    if (!mounted) return;
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('위치를 가져올 수 없어요. 위치 권한을 확인해 주세요.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _RecordSheet(
        position: pos,
        recordUpload: _recordUpload,
        onDone: () {},
      ),
    );
    _retryLocation();
  }

  Future<void> _showOverlay() async {
    final status = await Permission.systemAlertWindow.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _status = '다른 앱 위에 표시 권한이 필요합니다');
      return;
    }
    await FlutterOverlayWindow.showOverlay(
      height: 80,
      width: 80,
      alignment: OverlayAlignment.centerRight,
      visibility: NotificationVisibility.visibilityPublic,
      flag: OverlayFlag.defaultFlag,
      enableDrag: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_audioServiceReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('소리 Sori')),
        body: SafeArea(
          child: Center(
          child: _status.startsWith('오디오') || _status.contains('권한') || _status.contains('표시')
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(_status, textAlign: TextAlign.center),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('소리 Sori'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSettingsDropdowns(context),
            Expanded(
              child: _buildListenableList(),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton.filled(
                    onPressed: _openRecordSheet,
                    icon: const Icon(Icons.add),
                    tooltip: '녹음하기',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _startListening,
                      icon: const Icon(Icons.radio),
                      label: const Text('수신 시작'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonal(
                    onPressed: _showOverlay,
                    child: const Text('플로팅'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsDropdowns(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurface;
    final labelStyle = TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.8));
    final valueStyle = TextStyle(fontSize: 12, color: textColor);

    final radiusLabel = RadiusOption.values
        .firstWhere(
          (o) => (_settings.radiusKm <= 0 && o.km <= 0) || (_settings.radiusKm > 0 && (o.km - _settings.radiusKm).abs() < 0.01),
          orElse: () => RadiusOption.values.first,
        )
        .label;
    final languageLabel = LanguageOption.values
        .firstWhere(
          (o) => o.value == _settings.languageFilter,
          orElse: () => LanguageOption.values.first,
        )
        .label;
    final tensionLabel = TensionOption.values
        .firstWhere(
          (o) => o.value == _settings.tensionFilter,
          orElse: () => TensionOption.values.first,
        )
        .label;
    final durationLabel = DurationFilterOption.values
        .firstWhere(
          (o) => o.seconds == _settings.durationFilterSeconds,
          orElse: () => DurationFilterOption.values.first,
        )
        .label;

    Widget filterButton({
      required String label,
      required String value,
      required List<MenuItemButton> menuItems,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: MenuAnchor(
            consumeOutsideTap: false,
            builder: (ctx, controller, child) => InkWell(
              onTap: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: labelStyle, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(value, style: valueStyle, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                  ],
                ),
              ),
            ),
            menuChildren: menuItems,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          filterButton(
            label: '구분',
            value: _settings.mode,
            menuItems: [
              MenuItemButton(
                onPressed: () => _saveSettings(_settings.copyWith(mode: '전체')),
                child: const Text('전체'),
              ),
              MenuItemButton(
                onPressed: () => _saveSettings(_settings.copyWith(mode: '거주자')),
                child: const Text('거주자'),
              ),
              MenuItemButton(
                onPressed: () => _saveSettings(_settings.copyWith(mode: '여행자')),
                child: const Text('여행자'),
              ),
            ],
          ),
          filterButton(
            label: '거리',
            value: radiusLabel,
            menuItems: RadiusOption.values.map((o) => MenuItemButton(
              onPressed: () {
                _saveSettings(_settings.copyWith(radiusKm: o.km));
              },
              child: Text(o.label),
            )).toList(),
          ),
          filterButton(
            label: '언어',
            value: languageLabel,
            menuItems: LanguageOption.values.map((o) => MenuItemButton(
              onPressed: () {
                _saveSettings(_settings.copyWith(languageFilter: o.value));
              },
              child: Text(o.label),
            )).toList(),
          ),
          filterButton(
            label: '텐션',
            value: tensionLabel,
            menuItems: TensionOption.values.map((o) => MenuItemButton(
              onPressed: () {
                _saveSettings(_settings.copyWith(tensionFilter: o.value));
              },
              child: Text(o.label),
            )).toList(),
          ),
          filterButton(
            label: '재생시간',
            value: durationLabel,
            menuItems: DurationFilterOption.values.map((o) => MenuItemButton(
              onPressed: () {
                if (o.seconds == null) {
                  _saveSettings(_settings.copyWith(clearDurationFilter: true));
                } else {
                  _saveSettings(_settings.copyWith(durationFilterSeconds: o.seconds));
                }
              },
              child: Text(o.label),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildListenableList() {
    if (_positionFuture == null) return const Center(child: CircularProgressIndicator());
    return FutureBuilder<Position?>(
      future: _positionFuture,
      builder: (context, posSnap) {
        if (!posSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (posSnap.data == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('위치 권한이 필요해요', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () async {
                    final ok = await _location.requestPermission();
                    if (mounted && ok) _retryLocation();
                  },
                  icon: const Icon(Icons.location_on),
                  label: const Text('위치 권한 허용'),
                ),
              ],
            ),
          );
        }
        final pos = posSnap.data!;
        final lat = pos.latitude;
        final lng = pos.longitude;
        final radiusKm = _settings.effectiveRadiusKm;
        final useFixedCenter = radiusKm >= 10000;
        final queryLat = useFixedCenter ? 36.5 : lat;
        final queryLng = useFixedCenter ? 127.5 : lng;

        return StreamBuilder<List<SoriPost>>(
          key: ValueKey(_listRefreshKey),
          stream: _repo.watchNearby(
            latitude: queryLat,
            longitude: queryLng,
            radiusKm: radiusKm,
            modeFilter: _settings.mode != '전체' ? _settings.mode : null,
            languageFilter: _settings.languageFilter,
            tensionFilter: _settings.tensionFilter,
            durationFilterSeconds: _settings.durationFilterSeconds,
          ),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final posts = snap.data ?? [];
            if (posts.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refreshList,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height - 200,
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.earbuds_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 8),
                      Text('들릴 소리가 없어요', style: Theme.of(context).textTheme.bodyLarge),
                      const SizedBox(height: 4),
                      Text('설정에서 반경·필터를 바꾸거나\n수신 시작으로 백그라운드에서 들어보세요.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('진단 정보', style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Text('위치: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}', style: Theme.of(context).textTheme.bodySmall),
                            Text('반경: ${_settings.effectiveRadiusKm}km', style: Theme.of(context).textTheme.bodySmall),
                            Text('필터: 구분=${_settings.mode}, 언어=${_settings.languageFilter ?? '전체'}, 텐션=${_settings.tensionFilter ?? '전체'}, 재생시간=${_settings.durationFilterSeconds ?? '전체'}', style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 8),
                            Text('Firestore sori_posts에 position 필드가 있는 문서가 반경 내에 있어야 합니다.', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
            }
            return RefreshIndicator(
              onRefresh: _refreshList,
              child: _PostListContent(
              posts: posts,
              currentLat: lat,
              currentLng: lng,
              currentPlayingUrl: _currentPlayingUrl,
              currentPosition: _currentPosition,
              currentDuration: _currentDuration,
              isPlaying: _isPlaying,
              formatDuration: _formatDuration,
              formatDistance: _formatDistance,
              timeAgo: _timeAgo,
              showRecordSettings: true,
              onStop: () {
                _queueService.stopCurrent();
                setState(() {
                  _currentPlayingUrl = null;
                  _isPlaying = false;
                  _currentPosition = Duration.zero;
                  _currentDuration = null;
                });
                _positionUpdateTimer?.cancel();
              },
              onPlayPause: (post) {
                if (_currentPlayingUrl == post.audioUrl) {
                  if (_isPlaying) {
                    _queueService.pause();
                    setState(() => _isPlaying = false);
                  } else {
                    _queueService.play();
                    setState(() => _isPlaying = true);
                  }
                  return;
                }
                setState(() {
                  _currentPlayingUrl = post.audioUrl;
                  _isPlaying = true;
                  _isLoadingPlay = true;
                  _currentPosition = Duration.zero;
                  _currentDuration = null;
                });
                _positionUpdateTimer?.cancel();
                _positionUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
                  if (!mounted) return;
                  final h = _queueService.handler;
                  if (h != null) {
                    setState(() {
                      _currentPosition = h.currentPosition;
                      _currentDuration = h.currentDuration;
                    });
                  }
                });
                _queueService.playSingleUrl(post.audioUrl);
              },
            ),
            );
          },
        );
      },
    );
  }

  String _timeAgo(DateTime dateTime) {
    final d = DateTime.now().difference(dateTime);
    if (d.inMinutes < 1) return '방금 전';
    if (d.inHours < 1) return '${d.inMinutes}분 전';
    if (d.inDays < 1) return '${d.inHours}시간 전';
    return '${d.inDays}일 전';
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  String _formatDistance(double fromLat, double fromLng, double toLat, double toLng) {
    final meters = Geolocator.distanceBetween(fromLat, fromLng, toLat, toLng);
    if (meters < 1000) {
      return '${meters.round()}m';
    }
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  @override
  void dispose() {
    _positionUpdateTimer?.cancel();
    _queueService.stop();
    super.dispose();
  }
}

/// 재생 상태를 인자로 받아 목록만 그리는 위젯. 상태 변경 시 부모가 새 인자로 다시 빌드해 목록이 갱신되도록 함.
class _PostListContent extends StatelessWidget {
  const _PostListContent({
    required this.posts,
    required this.currentLat,
    required this.currentLng,
    required this.currentPlayingUrl,
    required this.currentPosition,
    required this.currentDuration,
    required this.isPlaying,
    required this.formatDuration,
    required this.formatDistance,
    required this.timeAgo,
    required this.onPlayPause,
    required this.onStop,
    this.showRecordSettings = false,
  });

  final List<SoriPost> posts;
  final double currentLat;
  final double currentLng;
  final String? currentPlayingUrl;
  final Duration currentPosition;
  final Duration? currentDuration;
  final bool isPlaying;
  final String Function(Duration) formatDuration;
  final String Function(double, double, double, double) formatDistance;
  final String Function(DateTime) timeAgo;
  final void Function(SoriPost post) onPlayPause;
  final VoidCallback onStop;
  final bool showRecordSettings;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      itemCount: posts.length,
      itemBuilder: (context, i) {
        final post = posts[i];
        final isCurrentItem = currentPlayingUrl == post.audioUrl;
        final showProgress = isCurrentItem;
        final positionStr = formatDuration(currentPosition);
        final durationStr = currentDuration != null ? formatDuration(currentDuration!) : '-';
        final distanceStr = formatDistance(currentLat, currentLng, post.location.latitude, post.location.longitude);
        final namePrefix = post.userName != null && post.userName!.isNotEmpty ? '${post.userName} · ' : '';
        final settingsStr = showRecordSettings
            ? '$namePrefix${post.mode} · ${post.languageLabel} · ${post.tensionLabel}${post.ttlLabel != null ? ' · ${post.ttlLabel}' : ''}'
            : '$namePrefix${post.languageLabel} · ${post.tensionLabel}';
        final durationLabel = post.durationLabel;
        return ListTile(
          selected: false,
          minLeadingWidth: isCurrentItem ? 88 : 40,
          leading: SizedBox(
            width: isCurrentItem ? 88 : 40,
            height: 40,
            child: isCurrentItem
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: isPlaying ? '일시중지' : '재생',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => onPlayPause(post),
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: '정지',
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onStop,
                            customBorder: const CircleBorder(),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.stop,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Tooltip(
                    message: '재생',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onPlayPause(post),
                        customBorder: const CircleBorder(),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.play_arrow,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
          ),
          title: Text(
            showProgress ? '$positionStr / $durationStr' : settingsStr,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          subtitle: Text(
            '$distanceStr${durationLabel.isNotEmpty ? ' · $durationLabel' : ''} · ${timeAgo(post.createdAt)}',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        );
      },
    );
  }
}

/// 녹음 바텀시트: 설정 → 녹음 → 업로드
class _RecordSheet extends StatefulWidget {
  const _RecordSheet({
    required this.position,
    required this.recordUpload,
    required this.onDone,
  });

  final Position position;
  final RecordUploadService recordUpload;
  final VoidCallback onDone;

  @override
  State<_RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<_RecordSheet> {
  bool _isRecording = false;
  bool _isUploading = false;
  late RecordSettings _recordSettings;
  late TextEditingController _userNameController;
  final RecordSettingsService _recordSettingsService = RecordSettingsService();
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadRecordSettings();
  }

  @override
  void dispose() {
    _userNameController.dispose();
    super.dispose();
  }

  Future<void> _loadRecordSettings() async {
    final s = await _recordSettingsService.load();
    if (mounted) {
      _recordSettings = s;
      _userNameController = TextEditingController(text: s.userName ?? '');
      setState(() => _settingsLoaded = true);
    }
  }

  Future<void> _saveRecordSettings() async {
    _recordSettings = _recordSettings.copyWith(
      userName: _userNameController.text.trim().isEmpty ? null : _userNameController.text.trim(),
    );
    await _recordSettingsService.save(_recordSettings);
  }

  Future<void> _startRecording() async {
    final started = await widget.recordUpload.startRecording();
    if (mounted) setState(() => _isRecording = started);
    if (!started && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('마이크 권한이 필요해요')),
      );
    }
  }

  Future<void> _stopAndUpload() async {
    if (!widget.recordUpload.isRecording) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isUploading = true);
    String? successMessage;
    String? errorMessage;
    try {
      await _saveRecordSettings();
      final id = await widget.recordUpload.stopRecordingAndUpload(
        latitude: widget.position.latitude,
        longitude: widget.position.longitude,
        settings: _recordSettings,
      ).timeout(
        const Duration(seconds: 90),
        onTimeout: () => throw TimeoutException('업로드 시간 초과'),
      );
      successMessage = id != null ? '업로드 완료' : null;
      if (id == null) errorMessage = '녹음 파일이 없어 업로드하지 못했어요';
    } on TimeoutException {
      errorMessage = '업로드 시간이 초과됐어요. 네트워크를 확인해 주세요.';
    } catch (e) {
      errorMessage = '업로드 실패: ${e.toString().split('\n').first}';
    } finally {
      try {
        if (mounted) await navigator.maybePop();
      } catch (_) {}
      widget.onDone();
      if (successMessage != null) {
        messenger.showSnackBar(SnackBar(content: Text(successMessage)));
      }
      if (errorMessage != null) {
        messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) {
      return const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isUploading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    const Text('업로드 중…'),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context, rootNavigator: true).maybePop(),
                      child: const Text('닫기 (백그라운드에서 계속 업로드됨)'),
                    ),
                  ],
                ),
              )
            else if (!_isRecording) ...[
              const SizedBox(height: 8),
              Text('사용자명', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              TextField(
                controller: _userNameController,
                decoration: const InputDecoration(
                  hintText: '이름 또는 닉네임',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text('모드', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: '거주자', label: Text('거주자')),
                  ButtonSegment(value: '여행자', label: Text('여행자')),
                ],
                selected: {_recordSettings.mode},
                onSelectionChanged: (v) => setState(() => _recordSettings = _recordSettings.copyWith(mode: v.first)),
              ),
              const SizedBox(height: 16),
              Text('언어', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: LanguageOption.values.where((o) => o.value != null).map((opt) {
                  final isSelected = _recordSettings.language == opt.value;
                  return ChoiceChip(
                    label: Text(opt.label),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _recordSettings = _recordSettings.copyWith(language: opt.value!)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text('텐션', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: TensionOption.values.where((o) => o.value != null).map((opt) {
                  final isSelected = _recordSettings.tension == opt.value;
                  return ChoiceChip(
                    label: Text(opt.label),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _recordSettings = _recordSettings.copyWith(tension: opt.value!)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text('유지시간', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: TtlOption.values.map((opt) {
                  final isSelected = (_recordSettings.ttlHours - opt.hours).abs() < 0.01;
                  return ChoiceChip(
                    label: Text(opt.label),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _recordSettings = _recordSettings.copyWith(ttlHours: opt.hours)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _startRecording,
                icon: const Icon(Icons.mic),
                label: const Text('녹음 시작'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              ),
            ] else ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _stopAndUpload,
                icon: const Icon(Icons.stop),
                label: const Text('완료하고 올리기'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 플로팅 오버레이 전용 엔트리포인트 (flutter_overlay_window에서 호출)
@pragma("vm:entry-point")
void overlayMain() {
  runApp(const OverlayApp());
}
