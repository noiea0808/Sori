import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_core/firebase_core.dart';

import 'overlay_main.dart';
import 'models/listen_settings.dart';
import 'screens/settings_screen.dart';
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
  await Firebase.initializeApp();

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
          : _settings!.hasCompletedOnboarding
              ? HomePage(initialSettings: _settings!)
              : SettingsScreen(
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
  const HomePage({super.key, required this.initialSettings});

  final ListenSettings initialSettings;

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
  String _status = '시작하기';
  Future<Position?>? _positionFuture;
  Timer? _positionUpdateTimer;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
    _positionFuture = _location.getCurrentPosition();
    _initAudioService();
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

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initialSettings: _settings,
          onSave: (s) async {
            await _settingsService.save(s);
            if (mounted) setState(() => _settings = s);
          },
        ),
      ),
    );
    _refreshSettings();
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
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_status, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('소리 Sori'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
            tooltip: '들을 소리 설정',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              _status,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ),
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
            padding: const EdgeInsets.all(16),
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
        final lat = posSnap.data!.latitude;
        final lng = posSnap.data!.longitude;

        return StreamBuilder<List<SoriPost>>(
          stream: _repo.watchNearby(
            latitude: lat,
            longitude: lng,
            radiusKm: _settings.effectiveRadiusKm,
            languageFilter: _settings.languageFilter,
            tensionFilter: _settings.tensionFilter,
          ),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final posts = snap.data ?? [];
            if (posts.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.earbuds_outlined, size: 48, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 8),
                    Text('들릴 소리가 없어요', style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 4),
                    Text('설정에서 반경·필터를 바꾸거나\n수신 시작으로 백그라운드에서 들어보세요.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              );
            }
            return _PostListContent(
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
          minLeadingWidth: isCurrentItem ? 96 : 48,
          leading: isCurrentItem
              ? SizedBox(
                  width: 96,
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: isPlaying ? '일시중지' : '재생',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => onPlayPause(post),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                alignment: Alignment.center,
                                child: Icon(
                                  isPlaying ? Icons.pause : Icons.play_arrow,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        color: Theme.of(context).dividerColor,
                      ),
                      Expanded(
                        child: Tooltip(
                          message: '정지',
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onStop,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                alignment: Alignment.center,
                                child: const Icon(Icons.stop, size: 24),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : SizedBox(
                  width: 48,
                  height: 48,
                  child: CircleAvatar(
                    child: IconButton(
                      style: IconButton.styleFrom(
                        minimumSize: const Size(24, 24),
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      iconSize: 20,
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => onPlayPause(post),
                      tooltip: '재생',
                    ),
                  ),
                ),
          title: Text(showProgress ? '$positionStr / $durationStr' : settingsStr),
          subtitle: Text('$distanceStr${durationLabel.isNotEmpty ? ' · $durationLabel' : ''} · ${timeAgo(post.createdAt)}'),
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
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        widget.onDone();
        if (successMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(successMessage)));
        }
        if (errorMessage != null) {
          messenger.showSnackBar(SnackBar(content: Text(errorMessage)));
        }
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
            Text(
              _isRecording ? '녹음 중…' : '소리 남기기',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            if (_isUploading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    const Text('업로드 중… (최대 90초)'),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => widget.onDone(),
                      child: const Text('닫기'),
                    ),
                  ],
                ),
              )
            else if (!_isRecording) ...[
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
            ] else
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
