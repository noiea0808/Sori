import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// 움직임 감지 후 GPS 활성화 임계 (m/s², 중력 제거 가속도 크기)
const double _motionThreshold = 0.4;

/// 이 시간 동안 움직임이 없으면 GPS 비활성화
const Duration _stationaryDuration = Duration(seconds: 60);

/// 가속도 샘플 주기 (배터리 절약)
const Duration _accelSamplingPeriod = Duration(milliseconds: 500);

/// 위치 권한 및 현재 위치 조회.
/// [positionStream]은 가속도 센서로 움직임이 감지될 때만 GPS를 켜고,
/// 일정 시간 움직임이 없으면 GPS를 끄는 지연 업데이트 방식으로 동작합니다.
class LocationService {
  StreamController<Position>? _positionController;
  Stream<Position>? _positionStreamCache;
  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<Position>? _gpsSub;
  Timer? _stationaryTimer;
  bool _gpsActive = false;
  DateTime? _lastMotionAt;

  Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<Position?> getCurrentPosition() async {
    final ok = await requestPermission();
    if (!ok) return null;
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
      timeLimit: const Duration(seconds: 10),
    );
  }

  /// 움직임이 감지될 때만 GPS를 켜고, [ _stationaryDuration ] 동안
  /// 움직임이 없으면 GPS를 끄는 위치 스트림.
  Stream<Position> get positionStream {
    _positionStreamCache ??= _createMotionAwarePositionStream();
    return _positionStreamCache!;
  }

  Stream<Position> _createMotionAwarePositionStream() {
    final c = StreamController<Position>(
      onListen: () {
        if (_positionController != null) {
          _onPositionStreamListen(_positionController!);
        }
      },
      onCancel: _onPositionStreamCancel,
    );
    _positionController = c;
    return c.stream;
  }

  void _onPositionStreamListen(StreamController<Position> c) {
    _lastMotionAt = DateTime.now();
    _startGps(c);
    _startAccelerometer(c);
  }

  void _onPositionStreamCancel() {
    _stopAccelerometer();
    _stopGps();
    _stationaryTimer?.cancel();
    _stationaryTimer = null;
    _positionController = null;
    _positionStreamCache = null;
  }

  void _startAccelerometer(StreamController<Position> c) {
    _accelSub?.cancel();
    _accelSub = userAccelerometerEventStream(
      samplingPeriod: _accelSamplingPeriod,
    ).listen((event) {
      final magnitude = math.sqrt(
        event.x * event.x + event.y * event.y + event.z * event.z,
      );
      if (magnitude > _motionThreshold) {
        _lastMotionAt = DateTime.now();
        _stationaryTimer?.cancel();
        _stationaryTimer = null;
        if (!_gpsActive) {
          _startGps(c);
        }
      } else {
        if (_stationaryTimer == null && _gpsActive) {
          _stationaryTimer = Timer(_stationaryDuration, () {
            _stationaryTimer = null;
            _stopGps();
          });
        }
      }
    });
  }

  void _stopAccelerometer() {
    _accelSub?.cancel();
    _accelSub = null;
  }

  void _startGps(StreamController<Position> c) {
    if (_gpsActive) return;
    _gpsActive = true;
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 30),
      ),
    ).listen(
      (position) {
        if (c.isClosed) return;
        c.add(position);
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _stopGps() {
    _gpsSub?.cancel();
    _gpsSub = null;
    _gpsActive = false;
  }
}
