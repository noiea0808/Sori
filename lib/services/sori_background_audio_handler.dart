import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

import '../config/app_config.dart';

/// 백그라운드 오디오 재생: 시그널 사운드 → 본 음성 스트리밍, Audio Ducking 적용
class SoriBackgroundAudioHandler extends BaseAudioHandler {
  final AudioPlayer _player = AudioPlayer();

  SoriBackgroundAudioHandler() {
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);
    _player.processingStateStream.listen(_onProcessingStateChanged);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  /// 앱에서 URL로 재생할 때 호출 (시그널 포함)
  Future<void> playUrl(String url) async {
    mediaItem.add(MediaItem(
      id: url,
      title: 'Sori',
      artUri: null,
    ));
    await _playWithSignal(url);
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    this.mediaItem.add(mediaItem);
    await _playWithSignal(mediaItem.id);
  }

  /// 새 음성 재생 전 0.5초 시그널 재생 후 본 URL 스트리밍
  Future<void> _playWithSignal(String contentUrl) async {
    try {
      // 시그널 에셋이 있으면 재생, 없으면 짧은 대기 후 본 재생
      final signalPath = 'assets/audio/signal.mp3';
      try {
        await _player.setAsset(signalPath);
        _player.setLoopMode(LoopMode.one);
        await _player.play();
        await Future<void>.delayed(
          Duration(milliseconds: (AppConfig.signalDurationSeconds * 1000).round()),
        );
        await _player.setLoopMode(LoopMode.off);
        await _player.stop();
      } catch (_) {
        // signal.mp3 없으면 스킵
        await Future<void>.delayed(
          Duration(milliseconds: (AppConfig.signalDurationSeconds * 1000).round()),
        );
      }

      await _player.setUrl(contentUrl);
      await _player.play();
    } catch (e) {
      playbackState.add(playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.error,
        controls: [],
      ));
    }
  }

  void _onProcessingStateChanged(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.idle,
          controls: [],
        ));
        break;
      case ProcessingState.loading:
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
        ));
        break;
      case ProcessingState.buffering:
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.buffering,
        ));
        break;
      case ProcessingState.ready:
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.ready,
          controls: [
            MediaControl.pause,
            MediaControl.stop,
          ],
        ));
        break;
      case ProcessingState.completed:
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.completed,
          playing: false,
          controls: [],
        ));
        break;
      case ProcessingState.error:
        playbackState.add(playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
          controls: [],
        ));
        break;
    }
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.pause,
        MediaControl.stop,
      ],
      systemUpdate: event.systemUpdate,
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
        ProcessingState.error: AudioProcessingState.error,
      }[event.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}

/// 오디오 세션 설정: 다른 앱 소리 Ducking
Future<void> configureAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(
    const AudioSessionConfiguration.speech().copyWith(
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ),
  );
}
